"""Whole-knowledge-base context for small tenants (opt-in per tenant: "context_mode": "full" in tenants.json).

When a tenant's base fits the bounds, every chunk goes into the stable part of the prompt, so Ollama can reuse the
KV cache of the whole prefix and each request only pays for the question and history. Correctness never depends on
that cache: the prompt is complete either way, only slower when the cache is cold or was evicted.

The snapshot is keyed by a fingerprint of the registry manifest plus the tenant's chunk count in Qdrant, so any sync,
upsert or delete (including writes that bypass the registry) invalidates it on the next request.
"""
import asyncio
import hashlib
import time
from dataclasses import dataclass, field

from app.retrieval.store import KnowledgeStore
from app.services.registry import DocumentRegistry


@dataclass(frozen=True)
class TenantContext:
    tenant_id: str
    fingerprint: str
    eligible: bool
    reason: str
    estimated_tokens: int
    documents: list[dict] = field(default_factory=list)


class FullContextCache:
    def __init__(self, store: KnowledgeStore, registry: DocumentRegistry | None, *, max_tokens: int,
                 max_chunks: int, chars_per_token: float):
        self.store = store
        self.registry = registry
        self.max_tokens = max_tokens
        self.max_chunks = max_chunks
        self.chars_per_token = chars_per_token
        self._cache: dict[str, TenantContext] = {}
        self._locks: dict[str, asyncio.Lock] = {}
        self.hits = 0
        self.rebuilds = 0
        self.last_build_ms = 0

    def estimate_tokens(self, documents: list[dict]) -> int:
        # Section + wrapper markup per chunk is counted too (~12 tokens).
        chars = sum(len(str(d.get("text") or "")) + len(str(d.get("section") or "")) for d in documents)
        return int(chars / self.chars_per_token) + 12 * len(documents)

    async def fingerprint(self, tenant_id: str) -> str:
        h = hashlib.sha256(tenant_id.encode())
        if self.registry is not None:
            for e in self.registry.manifest(tenant_id):
                h.update(f"|{e.document_id}:{e.version}:{e.content_hash}:{e.status}:{e.chunks}".encode())
        h.update(f"|n={await self.store.tenant_count(tenant_id)}".encode())
        return h.hexdigest()

    def invalidate(self, tenant_id: str) -> None:
        self._cache.pop(tenant_id, None)

    async def get(self, tenant_id: str) -> TenantContext:
        fp = await self.fingerprint(tenant_id)
        cached = self._cache.get(tenant_id)
        if cached is not None and cached.fingerprint == fp:
            self.hits += 1
            return cached
        lock = self._locks.setdefault(tenant_id, asyncio.Lock())
        async with lock:
            cached = self._cache.get(tenant_id)
            if cached is not None and cached.fingerprint == fp:
                self.hits += 1
                return cached
            started = time.perf_counter()
            documents = await self.store.all_chunks(tenant_id, self.max_chunks)
            estimated = self.estimate_tokens(documents)
            if not documents:
                ctx = TenantContext(tenant_id, fp, False, "empty", 0)
            elif len(documents) > self.max_chunks:
                ctx = TenantContext(tenant_id, fp, False, "too_many_chunks", estimated)
            elif estimated > self.max_tokens:
                ctx = TenantContext(tenant_id, fp, False, "too_many_tokens", estimated)
            else:
                ctx = TenantContext(tenant_id, fp, True, "ok", estimated, documents)
            self._cache[tenant_id] = ctx
            self.rebuilds += 1
            self.last_build_ms = int((time.perf_counter() - started) * 1000)
            return ctx
