import asyncio
import hashlib
from collections import defaultdict
from typing import Callable

from app.domain.models import KnowledgeDocument, SyncOperation
from app.embeddings.encoder import Encoder
from app.retrieval.chunking import chunk_document
from app.retrieval.sanitize import strip_instructions
from app.retrieval.store import KnowledgeStore
from app.services.registry import DocumentRegistry


def content_sha256(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


class KnowledgeService:
    def __init__(self, encoder: Encoder, store: KnowledgeStore, registry: DocumentRegistry | None = None,
                 on_change: Callable[[str], None] | None = None):
        self.encoder = encoder
        self.store = store
        self.registry = registry
        self.on_change = on_change
        self._locks: dict[str, asyncio.Lock] = defaultdict(asyncio.Lock)

    def _changed(self, tenant_id: str) -> None:
        if self.on_change is not None:
            self.on_change(tenant_id)

    async def upsert(self, tenant_id: str, doc: KnowledgeDocument) -> dict:
        try:
            return await self._upsert(tenant_id, doc)
        finally:
            self._changed(tenant_id)

    async def _upsert(self, tenant_id: str, doc: KnowledgeDocument) -> dict:
        content, removed = strip_instructions(doc.content)
        chunks = chunk_document(doc.title, content, doc.content_type, max_chars=600)
        if not chunks:
            return {"document_id": doc.document_id, "chunks": 0, "skipped": "empty", "instruction_lines_removed": removed}
        vectors = await asyncio.to_thread(self.encoder.encode_documents, [(c.section, c.text) for c in chunks])
        result = await self.store.upsert_document(
            tenant_id=tenant_id, document_id=doc.document_id, title=doc.title, source=doc.source,
            version=doc.document_version, chunks=chunks, vectors=vectors,
        )
        return {**result, "instruction_lines_removed": removed}

    async def delete(self, tenant_id: str, document_ids: list[str]) -> int:
        try:
            return await self.store.delete_documents(tenant_id, document_ids)
        finally:
            self._changed(tenant_id)

    async def sync(self, tenant_id: str, op: SyncOperation) -> dict:
        """Apply one versioned operation. Safe to repeat: same version+hash is a no-op, older versions are ignored."""
        base = {"document_id": op.document_id, "version": op.version}
        async with self._locks[f"{tenant_id}:{op.document_id}"]:
            current = self.registry.get(tenant_id, op.document_id)
            is_delete = op.op == "delete" or op.status in ("inactive", "deleted")
            if current is not None:
                if op.version < current.version:
                    return {**base, "result": "stale_ignored", "current_version": current.version}
                if op.version == current.version:
                    if is_delete and current.status == "deleted":
                        return {**base, "result": "unchanged"}
                    if not is_delete and current.status == "active" and op.content_hash == current.content_hash:
                        return {**base, "result": "unchanged"}
                    return {**base, "result": "version_conflict", "current_version": current.version}

            if is_delete:
                removed = await self.store.delete_documents(tenant_id, [op.document_id])
                self.registry.put(tenant_id, op.document_id, op.version, op.content_hash or "", "deleted", op.updated_at, 0)
                self._changed(tenant_id)
                return {**base, "result": "deleted", "chunks_removed": removed}

            if not op.content or not op.title or not op.content_hash:
                return {**base, "result": "invalid", "error": "title_content_hash_required"}
            if content_sha256(op.content) != op.content_hash:
                return {**base, "result": "hash_mismatch"}
            outcome = await self.upsert(tenant_id, KnowledgeDocument(
                document_id=op.document_id, title=op.title, content=op.content, source="sync",
                document_version=op.version, content_type=op.content_type,
            ))
            chunks = int(outcome.get("chunks", 0))
            if chunks == 0:
                await self.store.delete_documents(tenant_id, [op.document_id])
            self.registry.put(tenant_id, op.document_id, op.version, op.content_hash, "active", op.updated_at, chunks)
            self._changed(tenant_id)
            return {**base, "result": "upserted", "chunks": chunks,
                    "instruction_lines_removed": outcome.get("instruction_lines_removed", 0)}
