"""Per-stage latency benchmark for the production prompt path (retrieval -> prompt -> Ollama prefill -> decode).

Runs inside the ai-api container with the same retrieval and prompt builder as /v1/respond, and calls Ollama directly
so runner options (num_thread) can be compared. For each configuration it measures:
  cold   : full prompt with a unique first line, so no KV-cache prefix can be reused (first message after a restart)
  warm   : real sequence of different questions, sharing only the stable prefix (normal traffic)
Prints JSON lines; never prints prompts or document text.
Usage:  docker compose exec -T ai-api python - [num_thread ...] < bench/stage_bench.py      (0 = Ollama default)
"""
import asyncio
import json
import sys
import time
import uuid

import httpx

from app.config.settings import get_settings
from app.embeddings.encoder import Encoder
from app.inference.gate import InferenceGate
from app.inference.ollama_client import OllamaClient
from app.prompts.builder import PromptParts, build_messages
from app.retrieval.store import KnowledgeStore
from app.security.auth import TenantRegistry
from app.services.responder import Responder

TENANT = "pizzaria_bella_massa"
QUESTIONS = ["Vocês oferecem Wi-Fi?", "Tem pizza grande?", "Quanto custa a calabresa grande?", "Vocês entregam no centro?"]


async def chat(client: httpx.AsyncClient, s, messages: list[dict], num_thread: int) -> dict:
    options = {"num_ctx": s.llm_num_ctx, "temperature": 0.0, "num_predict": 48}
    if num_thread:
        options["num_thread"] = num_thread
    started = time.perf_counter()
    r = await client.post("/api/chat", json={"model": s.llm_model, "messages": messages, "stream": False,
                                             "options": options, "keep_alive": s.llm_keep_alive})
    r.raise_for_status()
    d = r.json()
    prompt_ms = d.get("prompt_eval_duration", 0) / 1e6
    eval_ms = d.get("eval_duration", 0) / 1e6
    return {"wall_ms": int((time.perf_counter() - started) * 1000), "load_ms": int(d.get("load_duration", 0) / 1e6),
            "prompt_tokens": d.get("prompt_eval_count", 0), "prompt_eval_ms": int(prompt_ms),
            "prefill_tok_s": round(d.get("prompt_eval_count", 0) / (prompt_ms / 1000), 1) if prompt_ms else None,
            "completion_tokens": d.get("eval_count", 0), "eval_ms": int(eval_ms),
            "decode_tok_s": round(d.get("eval_count", 0) / (eval_ms / 1000), 1) if eval_ms else None}


async def main(threads: list[int]) -> None:
    s = get_settings()
    tenant = TenantRegistry.load(s.tenants_file).get(TENANT) or {}
    encoder = await asyncio.to_thread(Encoder, s.embedding_model, s.embedding_threads, s.embedding_dim)
    store = KnowledgeStore(s.qdrant_url, s.qdrant_api_key, s.qdrant_collection, encoder.dim, encoder.model_name)
    responder = Responder(s, encoder, store, OllamaClient(s.ollama_url, s.llm_timeout_s), InferenceGate(1, 1, 1, 1))

    prompts = []
    for q in QUESTIONS:
        t0 = time.perf_counter()
        docs = await responder.retrieve(TENANT, q, s.retrieval_top_k, s.retrieval_mode)
        retrieval_ms = int((time.perf_counter() - t0) * 1000)
        messages = build_messages(PromptParts(
            tenant_name=tenant.get("display_name", TENANT), tenant_profile=tenant.get("profile", ""),
            flow_state="", structured="", documents=docs, history=[], summary="", message=q))
        prompts.append((q, retrieval_ms, messages))

    async with httpx.AsyncClient(base_url=s.ollama_url, timeout=600) as client:
        for n in threads:
            await chat(client, s, [{"role": "user", "content": "ok"}], n)  # load runner with this option set
            q, retrieval_ms, messages = prompts[0]
            cold = [dict(messages[0], content=f"[bench {uuid.uuid4().hex}]\n" + messages[0]["content"])] + messages[1:]
            print(json.dumps({"num_thread": n or "default", "mode": "cold", "question": q,
                              "retrieval_ms": retrieval_ms, **await chat(client, s, cold, n)}))
            for q, retrieval_ms, messages in prompts:
                print(json.dumps({"num_thread": n or "default", "mode": "warm", "question": q,
                                  "retrieval_ms": retrieval_ms, **await chat(client, s, messages, n)}))
        await chat(client, s, [{"role": "user", "content": "ok"}], 0)  # leave the production runner loaded
    await store.client.close()


asyncio.run(main([int(a) for a in sys.argv[1:]] or [0]))
