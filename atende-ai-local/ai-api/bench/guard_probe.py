"""Replays a short conversation through Responder.respond and prints the raw model text next to the final answer and
the guard that fired, for one context mode. Diagnostic only: no persistence, nothing sent anywhere.
Usage:  docker compose exec -T ai-api python - <rag|full> < bench/guard_probe.py   (greeting JSON on fd 3 is optional)
"""
import asyncio
import json
import os
import sys
import time

from app.config.settings import get_settings
from app.domain.models import RespondRequest
from app.embeddings.encoder import Encoder
from app.inference.gate import InferenceGate
from app.inference.ollama_client import OllamaClient
from app.retrieval.store import KnowledgeStore
from app.security.auth import TenantRegistry
from app.services.full_context import FullContextCache
from app.services.registry import DocumentRegistry
from app.services.responder import Responder

TENANT = "pizzaria_bella_massa"
GREETING = os.environ.get("GREETING", "Oi! Bem-vindo à Pizzaria Bella Massa!")
TURNS = ["Vocês têm pizza grande?", "De calabresa", "Quanto custa?", "E a de frango?"]


class Tap(OllamaClient):
    last_text = ""

    async def chat(self, *a, **kw):
        gen = await super().chat(*a, **kw)
        Tap.last_text = gen.text
        return gen


async def main(mode: str) -> None:
    s = get_settings()
    tenant = dict(TenantRegistry.load(s.tenants_file).get(TENANT) or {}, context_mode=mode)
    encoder = await asyncio.to_thread(Encoder, s.embedding_model, s.embedding_threads, s.embedding_dim)
    store = KnowledgeStore(s.qdrant_url, s.qdrant_api_key, s.qdrant_collection, encoder.dim, encoder.model_name)
    cache = FullContextCache(store, DocumentRegistry(s.registry_path), max_tokens=s.full_context_max_tokens,
                             max_chunks=s.full_context_max_chunks, chars_per_token=s.full_context_chars_per_token)
    llm = Tap(s.ollama_url, s.llm_timeout_s)
    responder = Responder(s, encoder, store, llm, InferenceGate(1, 1, 300, 1), full_context=cache)
    history = [{"role": "user", "content": "Boa noite"}, {"role": "assistant", "content": GREETING}]
    for n, text in enumerate(TURNS, 1):
        req = RespondRequest(request_id=f"r-probe-{int(time.time())}-{n}", tenant_id=TENANT, conversation_id="c-probe",
                             message=text, recent_history=history + [{"role": "user", "content": text}])
        res = await responder.respond(req, TENANT, tenant)
        print(json.dumps({"mode": mode, "message": text, "guard": res.guard, "raw": Tap.last_text[:300],
                          "final": res.text[:200], "retrieval": res.retrieval.mode}, ensure_ascii=False))
        history += [{"role": "user", "content": text}, {"role": "assistant", "content": res.text}]
    await llm.close()
    await store.client.close()


asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "full"))
