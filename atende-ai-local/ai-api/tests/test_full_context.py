import asyncio

from app.config.settings import Settings
from app.domain.models import KnowledgeDocument, RespondRequest
from app.inference.gate import InferenceGate
from app.inference.ollama_client import Generation
from app.prompts.builder import PromptParts, build_messages
from app.services.full_context import FullContextCache
from app.services.knowledge import KnowledgeService, content_sha256
from app.services.registry import DocumentRegistry
from app.services.responder import FALLBACK_TEXT, Responder
from tests.test_phase2 import _op

BELLA, ZE = "pizzaria_bella_massa", "pastelaria_do_ze"


def _chunk(tenant, doc, text, index=0):
    return {"score": 1.0, "tenant_id": tenant, "document_id": doc, "document_version": 1, "section": doc,
            "chunk_id": f"{doc}:v1:{index}", "text": text, "source": "sync", "chunk_index": index}


class ChunkStore:
    """In-memory stand-in for KnowledgeStore keyed by tenant (same contract as the Qdrant store)."""

    def __init__(self):
        self.chunks: dict[str, list[dict]] = {}
        self.searches = 0

    def add(self, tenant, doc, text, index=0):
        self.chunks.setdefault(tenant, []).append(_chunk(tenant, doc, text, index))

    async def all_chunks(self, tenant_id, limit):
        out = [dict(c) for c in self.chunks.get(tenant_id, [])][: limit + 1]
        return sorted(out, key=lambda d: (d["document_id"], d["chunk_index"]))

    async def tenant_count(self, tenant_id):
        return len(self.chunks.get(tenant_id, []))

    async def search(self, tenant_id, vec, query, top_k, mode, min_score=0.0):
        self.searches += 1
        return [dict(c) for c in self.chunks.get(tenant_id, [])][:top_k]

    async def upsert_document(self, tenant_id, document_id, title, source, version, chunks, vectors):
        self.chunks[tenant_id] = [c for c in self.chunks.get(tenant_id, []) if c["document_id"] != document_id]
        for ch in chunks:
            self.add(tenant_id, document_id, ch.text, ch.index)
        return {"document_id": document_id, "chunks": len(chunks), "version": version}

    async def delete_documents(self, tenant_id, document_ids):
        before = len(self.chunks.get(tenant_id, []))
        self.chunks[tenant_id] = [c for c in self.chunks.get(tenant_id, []) if c["document_id"] not in document_ids]
        return before - len(self.chunks[tenant_id])


class Encoder:
    def encode_documents(self, items):
        return [[0.0] for _ in items]

    def encode_queries(self, items):
        return [[0.0] for _ in items]


class LLM:
    def __init__(self, reply="A calabresa grande custa R$ 62,90."):
        self.reply = reply
        self.messages = None

    async def chat(self, model, messages, **kw):
        self.messages = messages
        return Generation(text=self.reply, model=model, prompt_tokens=100, completion_tokens=10, load_ms=0,
                          first_token_ms=1, total_ms=5, eval_ms=3, prompt_eval_ms=2)


def _cache(store, registry=None, max_tokens=1800, max_chunks=40):
    return FullContextCache(store, registry, max_tokens=max_tokens, max_chunks=max_chunks, chars_per_token=3.0)


def _store():
    store = ChunkStore()
    store.add(BELLA, "precos", "Calabresa grande R$ 62,90. Mussarela grande R$ 59,90.")
    store.add(BELLA, "entrega", "Entregamos no centro. Taxa de entrega R$ 6,00.")
    store.add(ZE, "precos", "Pastel de carne R$ 9,00.")
    return store


def test_full_context_contains_only_the_tenant_documents_in_stable_order():
    async def scenario():
        ctx = await _cache(_store()).get(BELLA)
        assert ctx.eligible and ctx.reason == "ok"
        assert [d["document_id"] for d in ctx.documents] == ["entrega", "precos"]
        assert all(d["tenant_id"] == BELLA for d in ctx.documents)
        assert "Pastel" not in " ".join(d["text"] for d in ctx.documents)
    asyncio.run(scenario())


def test_full_context_falls_back_when_base_is_too_large_or_empty():
    async def scenario():
        store = _store()
        assert (await _cache(store, max_tokens=10).get(BELLA)).reason == "too_many_tokens"
        assert (await _cache(store, max_chunks=1).get(BELLA)).reason == "too_many_chunks"
        assert (await _cache(store).get("tenant_sem_base")).reason == "empty"
    asyncio.run(scenario())


def test_snapshot_is_reused_and_invalidated_by_sync_and_direct_writes():
    async def scenario():
        store, registry = _store(), DocumentRegistry(":memory:")
        cache = _cache(store, registry)
        svc = KnowledgeService(Encoder(), store, registry, on_change=cache.invalidate)
        first = await cache.get(BELLA)
        assert (await cache.get(BELLA)) is first and cache.hits == 1

        await svc.sync(BELLA, _op(content="# Wi-Fi\n\nTemos Wi-Fi gratuito para clientes."))
        after_sync = await cache.get(BELLA)
        assert after_sync is not first
        assert any("Wi-Fi" in d["text"] for d in after_sync.documents)

        # Same chunk count, no registry entry: only the explicit invalidation can catch it.
        await svc.upsert(BELLA, KnowledgeDocument(document_id="entrega", title="Entrega", content="Não entregamos no centro.",
                                                  source="manual"))
        after_upsert = await cache.get(BELLA)
        assert any("Não entregamos" in d["text"] for d in after_upsert.documents)

        await svc.delete(BELLA, ["faq"])
        assert not any("Wi-Fi" in d["text"] for d in (await cache.get(BELLA)).documents)
    asyncio.run(scenario())


def test_other_tenant_writes_do_not_touch_the_snapshot():
    async def scenario():
        store, registry = _store(), DocumentRegistry(":memory:")
        cache = _cache(store, registry)
        svc = KnowledgeService(Encoder(), store, registry, on_change=cache.invalidate)
        first = await cache.get(BELLA)
        await svc.sync(ZE, _op(content="# Horário\n\nAbrimos às 7h."))
        assert (await cache.get(BELLA)) is first
    asyncio.run(scenario())


def _responder(store, llm=None, cache=None):
    return Responder(Settings(), Encoder(), store, llm or LLM(), InferenceGate(1, 1, 5, 1), full_context=cache)


def _req(message, tenant=BELLA):
    return RespondRequest(request_id="r-test-0001", tenant_id=tenant, message=message)


def test_context_mode_is_opt_in_per_tenant():
    async def scenario():
        store = _store()
        responder = _responder(store, cache=_cache(store))
        docs, mode, reason = await responder.context_documents(BELLA, {"context_mode": "full"}, "x", "hybrid")
        assert mode == "full_context" and len(docs) == 2 and store.searches == 0
        docs, mode, reason = await responder.context_documents(ZE, {}, "x", "hybrid")
        assert mode == "hybrid" and reason == "" and store.searches == 1
        small = _responder(store, cache=_cache(store, max_tokens=10))
        docs, mode, reason = await small.context_documents(BELLA, {"context_mode": "full"}, "x", "hybrid")
        assert mode == "hybrid" and reason == "too_many_tokens"
    asyncio.run(scenario())


def test_full_context_prompt_puts_documents_in_the_stable_prefix():
    docs = [_chunk(BELLA, "precos", "Calabresa grande R$ 62,90.")]
    common = dict(tenant_name="Bella", tenant_profile="p", flow_state="state", structured="Telefone: 1",
                  documents=docs, history=[], summary="", message="oi")
    full = build_messages(PromptParts(**common, documents_first=True))[0]["content"]
    rag = build_messages(PromptParts(**common))[0]["content"]
    docs_at, data_at, state_at = (full.index(m) for m in ("DOCUMENTOS DA EMPRESA", "DADOS OFICIAIS DA EMPRESA",
                                                           "ESTADO DO ATENDIMENTO:"))
    assert docs_at < data_at < state_at
    assert rag.index("DADOS OFICIAIS DA EMPRESA") < rag.index("DOCUMENTOS DA EMPRESA")
    warm = build_messages(PromptParts(tenant_name="Bella", tenant_profile="p", flow_state="", structured="",
                                      documents=docs, history=[], summary="", message="ok", documents_first=True))
    prefix = warm[0]["content"]
    assert full.startswith(prefix)


FULL = {"context_mode": "full", "display_name": "Pizzaria Bella Massa"}


def _deadline_req(n, deadline_ms=20000):
    return RespondRequest(request_id=f"r-test-{n:04d}", tenant_id=BELLA, message="Quanto custa a calabresa grande?",
                          options={"deadline_ms": deadline_ms})


def test_cold_prefix_that_does_not_fit_the_deadline_uses_rag_and_rewarms_in_background():
    async def scenario():
        store = _store()
        responder = Responder(Settings(full_context_rewarm_delay_s=0), Encoder(), store, LLM(), InferenceGate(1, 1, 5, 1),
                              full_context=_cache(store))
        first = await responder.respond(_deadline_req(1), BELLA, FULL)
        assert first.retrieval.mode == "hybrid" and first.retrieval.fallback_reason == "kv_cold"
        assert responder._rewarm is not None
        await responder._rewarm
        second = await responder.respond(_deadline_req(2), BELLA, FULL)
        assert second.retrieval.mode == "full_context" and second.retrieval.fallback_reason is None
        # A generous deadline can afford the cold prefill, so no RAG detour is needed.
        responder.note_kv(None)
        roomy = await responder.respond(_deadline_req(3, deadline_ms=180000), BELLA, FULL)
        assert roomy.retrieval.mode == "full_context"
    asyncio.run(scenario())


def test_customer_request_cancels_a_pending_rewarm():
    async def scenario():
        store = _store()
        responder = Responder(Settings(full_context_rewarm_delay_s=30), Encoder(), store, LLM(), InferenceGate(1, 1, 5, 1),
                              full_context=_cache(store))
        await responder.respond(_deadline_req(1), BELLA, FULL)
        pending = responder._rewarm
        assert pending is not None and not pending.done()
        await responder.respond(_deadline_req(2), BELLA, FULL)
        assert pending.cancelled()
        responder._rewarm.cancel()
    asyncio.run(scenario())


def test_readiness_does_not_probe_after_a_recent_real_inference():
    import time
    from app.services.readiness import Readiness

    async def scenario():
        llm, evicted = LLM(), []
        readiness = Readiness(Settings(), None, None, llm, recent_success=time.monotonic,
                              on_probe=lambda: evicted.append(True))
        await readiness._probe_inference()
        assert readiness._probe_ok and readiness._probe_detail.startswith("recent_inference")
        assert llm.messages is None and not evicted
        cold = Readiness(Settings(), None, None, llm, recent_success=lambda: 0.0, on_probe=lambda: evicted.append(True))
        await cold._probe_inference()
        assert evicted and llm.messages is not None
    asyncio.run(scenario())


def _turns(n):
    out = []
    for i in range(1, n + 1):
        out += [{"role": "user", "content": f"pergunta {i}"}, {"role": "assistant", "content": f"resposta {i}"}]
    return out


def test_sticky_history_grows_append_only_and_resets_after_twice_the_limit():
    from app.prompts.builder import StickyHistory
    sticky = StickyHistory()
    assert sticky.select("c1", _turns(1), 2, 700) == _turns(1)
    assert sticky.select("c1", _turns(2), 2, 700) == _turns(2)  # keeps its first message: shared prefix
    reset = sticky.select("c1", _turns(3), 2, 700)  # 6 messages > 2 x 2: restart from the tail
    assert reset == _turns(3)[-2:]
    assert sticky.select("c1", _turns(4), 2, 700) == _turns(4)[-4:]
    assert sticky.select("outra", _turns(4), 2, 700) == _turns(4)[-2:]  # conversations never share anchors
    assert StickyHistory().select(None, _turns(4), 2, 700) == _turns(4)[-2:]


def test_consecutive_full_context_prompts_share_the_previous_prompt_as_prefix():
    async def scenario():
        store, llm = _store(), LLM()
        responder = _responder(store, llm, _cache(store))
        prompts = []
        for n in range(1, 4):
            history = _turns(n - 1)
            req = RespondRequest(request_id=f"r-test-{n:04d}", tenant_id=BELLA, conversation_id="conv-1",
                                 message=f"pergunta {n}", recent_history=history)
            await responder.respond(req, BELLA, FULL)
            prompts.append(llm.messages)
        for previous, current in zip(prompts, prompts[1:]):
            assert current[: len(previous) - 1] == previous[:-1]
    asyncio.run(scenario())


def test_prompt_is_a_strict_prefix_of_the_next_turn_when_history_repeats_the_current_message():
    async def scenario():
        store, llm = _store(), LLM()
        responder = _responder(store, llm, _cache(store))
        prompts = []
        for n in range(1, 4):
            history = _turns(n - 1) + [{"role": "user", "content": f"pergunta {n}"}]
            req = RespondRequest(request_id=f"r-test-{n:04d}", tenant_id=BELLA, conversation_id="conv-2",
                                 message=f"pergunta {n}", recent_history=history)
            await responder.respond(req, BELLA, FULL)
            prompts.append(llm.messages)
        assert prompts[0][-1] == {"role": "user", "content": "pergunta 1"} and len(prompts[0]) == 2
        for previous, current in zip(prompts, prompts[1:]):
            assert current[: len(previous)] == previous
    asyncio.run(scenario())


def test_guards_still_apply_with_full_context():
    async def scenario():
        store = _store()
        tenant = {"context_mode": "full", "display_name": "Pizzaria Bella Massa"}
        ok = await _responder(store, cache=_cache(store)).respond(_req("Quanto custa a calabresa grande?"), BELLA, tenant)
        assert ok.text == "A calabresa grande custa R$ 62,90." and ok.retrieval.mode == "full_context"
        invented = await _responder(store, LLM("A calabresa grande custa R$ 49,90."), _cache(store)).respond(
            _req("Quanto custa a calabresa grande?"), BELLA, tenant)
        assert invented.text == FALLBACK_TEXT and invented.guard == "price_not_in_context"
        # Another tenant's price is never authorized context for Bella.
        foreign = await _responder(store, LLM("O pastel de carne custa R$ 9,00."), _cache(store)).respond(
            _req("Quanto custa o pastel?"), BELLA, tenant)
        assert foreign.text == FALLBACK_TEXT
    asyncio.run(scenario())
