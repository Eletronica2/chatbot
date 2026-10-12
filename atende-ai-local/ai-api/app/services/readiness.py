import asyncio
import time

from app.config.settings import Settings
from app.embeddings.encoder import Encoder
from app.inference.ollama_client import OllamaClient
from app.retrieval.store import KnowledgeStore


class Readiness:
    """Cheap checks on every call; the inference probe (1 token) is cached for ready_inference_ttl_s."""

    def __init__(self, settings: Settings, encoder: Encoder | None, store: KnowledgeStore, llm: OllamaClient,
                 registry=None):
        self.s = settings
        self.encoder = encoder
        self.store = store
        self.llm = llm
        self.registry = registry
        self._probe_at = 0.0
        self._probe_ok = False
        self._probe_detail = "not_run"
        self._lock = asyncio.Lock()

    async def _probe_inference(self) -> None:
        async with self._lock:
            if time.monotonic() - self._probe_at < self.s.ready_inference_ttl_s and self._probe_ok:
                return
            try:
                gen = await self.llm.chat(self.s.llm_model, [{"role": "user", "content": "Responda apenas: ok"}],
                                          num_ctx=512, temperature=0.0, max_tokens=2, keep_alive=self.s.llm_keep_alive)
                self._probe_ok = gen.completion_tokens > 0
                self._probe_detail = f"tokens={gen.completion_tokens} load_ms={gen.load_ms} total_ms={gen.total_ms}"
            except Exception as exc:
                self._probe_ok = False
                self._probe_detail = f"error: {str(exc)[:120]}"
            self._probe_at = time.monotonic()

    async def check(self) -> dict:
        checks: dict[str, dict] = {"fastapi": {"ok": True}}
        try:
            checks["qdrant"] = {"ok": await self.store.ping(), "collection": self.s.qdrant_collection}
        except Exception as exc:
            checks["qdrant"] = {"ok": False, "detail": str(exc)[:120]}
        try:
            models = await self.llm.list_models()
            checks["ollama"] = {"ok": True}
            checks["model"] = {"ok": self.s.llm_model in models, "name": self.s.llm_model}
        except Exception as exc:
            checks["ollama"] = {"ok": False, "detail": str(exc)[:120]}
            checks["model"] = {"ok": False, "name": self.s.llm_model}
        if self.registry is not None:
            try:
                checks["registry"] = {"ok": self.registry.ping()}
            except Exception as exc:
                checks["registry"] = {"ok": False, "detail": str(exc)[:120]}
        checks["embedding"] = {"ok": self.encoder is not None,
                               "name": self.encoder.model_name if self.encoder else self.s.embedding_model,
                               "dim": self.encoder.dim if self.encoder else None}
        if checks["model"]["ok"]:
            await self._probe_inference()
        checks["inference"] = {"ok": self._probe_ok, "detail": self._probe_detail,
                               "age_s": int(time.monotonic() - self._probe_at) if self._probe_at else None}
        return {"ready": all(c["ok"] for c in checks.values()), "checks": checks}
