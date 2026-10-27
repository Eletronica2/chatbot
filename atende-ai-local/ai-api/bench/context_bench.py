"""RAG vs full-context benchmark on the production code path (Responder.respond), same questions, same model.

Runs inside the ai-api container against the live Qdrant/registry (read-only) and Ollama, with its own inference
gate. Per mode it runs the question set in order (the first question pays the new prefix; the rest show steady
state), then evicts the KV cache with another tenant's prompt and asks once more (no assumption that Ollama kept it).
Quality is checked against facts from the tenant's knowledge base. Prints JSON lines.
Usage (one at a time; the caller holds a lock and a timeout):
    docker compose exec -T ai-api python - [rag] [full] < bench/context_bench.py
"""
import asyncio
import json
import re
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
from app.services.responder import FALLBACK_TEXT, Responder

TENANT, OTHER = "pizzaria_bella_massa", "pastelaria_do_ze"
UNKNOWN = FALLBACK_TEXT


def has(*needles):
    return lambda t: all(n.lower() in t.lower() for n in needles)


def any_of(*needles):
    return lambda t: any(n.lower() in t.lower() for n in needles)


def only_prices(allowed):
    return lambda t: bool(re.findall(r"\d+,\d{2}", t)) and set(re.findall(r"\d+,\d{2}", t)) <= set(allowed)


CASES = [
    ("Quanto custa a pizza de calabresa grande?", has("62,90")),
    ("Vocês têm pizza grande?", any_of("45", "grande")),
    # No size given: all three sizes must be in the answer.
    ("Qual o preço da calabresa?", lambda t: only_prices({"42,90", "52,90", "62,90"})(t) and has("42,90", "52,90", "62,90")(t)),
    ("Quanto custa uma pizza de frango?", only_prices({"46,90", "56,90", "66,90"})),
    ("Vocês oferecem Wi-Fi?", has(UNKNOWN)),
    ("Quanto custa a pizza de pepperoni?", lambda t: "pepperoni" not in t.lower() or t == UNKNOWN),
    ("Qual o horário de domingo?", has("22")),
    ("Aceita PIX?", has("pix")),
    ("Quem ganhou o jogo do Flamengo ontem?", has("Posso ajudar apenas")),
    # Long answers: the concise style must not cut what was asked for.
    ("Quais são os sabores de pizza doce?", has("chocolate", "banana", "prest", "nutella", "romeu")),
    ("Quais as formas de pagamento?", has("pix", "cart", "dinheiro")),
]


async def ask(responder, tenant_cfg, question, n, tenant=TENANT):
    req = RespondRequest(request_id=f"r-bench-{int(time.time())}-{n:04d}", tenant_id=tenant, message=question)
    started = time.perf_counter()
    res = await responder.respond(req, tenant, tenant_cfg)
    return res, int((time.perf_counter() - started) * 1000)


_OFFER_TAIL = re.compile(r"(quer|gostaria|deseja|que tal|posso (te )?(sugerir|mostrar|oferecer))[^.!?]*\?\W*$", re.I)


def row(mode, phase, question, res, wall, ok=None):
    return {"mode": mode, "phase": phase, "question": question, "ok": ok, "wall_ms": wall,
            "offer_tail": bool(_OFFER_TAIL.search(res.text)) and "encaminhar" not in res.text,
            "retrieval": res.retrieval.mode, "fallback_reason": res.retrieval.fallback_reason,
            "docs": res.retrieval.documents_used, "prompt_tokens": res.usage.prompt_tokens,
            "prompt_eval_ms": res.timings.prompt_eval_ms, "eval_ms": res.timings.eval_ms,
            "completion_tokens": res.usage.completion_tokens, "retrieval_ms": res.timings.retrieval_ms,
            "guard": res.guard, "answer": res.text[:160]}


async def main(modes):
    s = get_settings()
    tenants = TenantRegistry.load(s.tenants_file)
    encoder = await asyncio.to_thread(Encoder, s.embedding_model, s.embedding_threads, s.embedding_dim)
    store = KnowledgeStore(s.qdrant_url, s.qdrant_api_key, s.qdrant_collection, encoder.dim, encoder.model_name)
    cache = FullContextCache(store, DocumentRegistry(s.registry_path), max_tokens=s.full_context_max_tokens,
                             max_chunks=s.full_context_max_chunks, chars_per_token=s.full_context_chars_per_token)
    llm = OllamaClient(s.ollama_url, s.llm_timeout_s)
    responder = Responder(s, encoder, store, llm, InferenceGate(1, 1, 300, 1), full_context=cache)
    base = {k: v for k, v in (tenants.get(TENANT) or {}).items() if k not in ("context_mode", "response_style")}
    other = dict(tenants.get(OTHER) or {}, context_mode="rag")
    ctx = await cache.get(TENANT)
    print(json.dumps({"tenant": TENANT, "full_context_eligible": ctx.eligible, "reason": ctx.reason,
                      "estimated_tokens": ctx.estimated_tokens, "chunks": len(ctx.documents)}))
    n = 0
    for mode in modes:
        context_mode, _, style = mode.partition(":")
        cfg = dict(base, context_mode=context_mode, response_style=style or "standard")
        for i, (question, check) in enumerate(CASES):
            n += 1
            res, wall = await ask(responder, cfg, question, n)
            print(json.dumps(row(mode, "first" if i == 0 else "warm", question, res, wall, bool(check(res.text)))))
        n += 1
        await ask(responder, other, "Qual o horário?", n, tenant=OTHER)  # evict Bella's KV prefix
        n += 1
        question, check = CASES[0]
        res, wall = await ask(responder, cfg, question, n)
        print(json.dumps(row(mode, "after_eviction", question, res, wall, bool(check(res.text)))))
    await llm.close()
    await store.client.close()


asyncio.run(main([m for m in sys.argv[1:] if m.partition(":")[0] in ("rag", "full")] or ["rag", "full"]))
