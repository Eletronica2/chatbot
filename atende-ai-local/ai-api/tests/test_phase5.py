import asyncio

import pytest

from app.config.settings import Settings
from app.domain.models import RespondRequest
from app.inference.gate import InferenceGate
from app.prompts.builder import RESPONSE_STYLES, PromptParts, build_messages, style_rules_for
from app.services.responder import FALLBACK_TEXT, Responder, strip_unsolicited_offer
from tests.test_full_context import BELLA, LLM, Encoder, _cache, _store

CONCISE = {"context_mode": "full", "display_name": "Pizzaria Bella Massa", "response_style": "concise"}


def test_style_is_opt_in_per_tenant_and_part_of_the_stable_prefix():
    assert style_rules_for({}) == "" and style_rules_for({"response_style": "standard"}) == ""
    assert style_rules_for({"response_style": "concise"}) == RESPONSE_STYLES["concise"]
    common = dict(tenant_name="Bella", tenant_profile="p", flow_state="s", structured="", documents=[], history=[],
                  summary="", message="oi")
    concise = build_messages(PromptParts(**common, style_rules=RESPONSE_STYLES["concise"]))[0]["content"]
    standard = build_messages(PromptParts(**common))[0]["content"]
    assert "ESTILO DE RESPOSTA" in concise and "ESTILO DE RESPOSTA" not in standard
    assert concise.index("Perfil da empresa") < concise.index("ESTILO DE RESPOSTA") < concise.index("ESTADO DO ATENDIMENTO:")
    # Placeholders only: a concrete price in the example would be copied into other tenants' answers.
    assert "R$ <preço>" in RESPONSE_STYLES["concise"] and "62,90" not in RESPONSE_STYLES["concise"]


@pytest.mark.parametrize("answer, expected", [
    ("A pizza grande de calabresa custa R$ 62,90. Quer saber sobre outro sabor ou combo? 😊",
     "A pizza grande de calabresa custa R$ 62,90."),
    ("Sim, temos pizza grande (45 cm).  \nGostaria de ver os sabores?", "Sim, temos pizza grande (45 cm)."),
    ("Sim, aceitamos PIX. 🍕 Posso te sugerir uma bebida?", "Sim, aceitamos PIX. 🍕"),
])
def test_final_unsolicited_offer_is_removed(answer, expected):
    assert strip_unsolicited_offer(answer, "Quanto custa a pizza grande de calabresa?") == expected


@pytest.mark.parametrize("answer, message", [
    (FALLBACK_TEXT, "Vocês têm Wi-Fi?"),  # handoff offer stays
    ("A calabresa grande custa R$ 62,90.", "Quanto custa?"),  # nothing to remove
    ("Temos o Combo Família por R$ 89,90. Quer que eu explique o que vem?", "Quais combos vocês têm?"),  # asked for it
    ("Quer saber os sabores?", "Tem pizza?"),  # never empties the answer
    ("Broto R$ 42,90, média R$ 52,90 e grande R$ 62,90. Qual tamanho você prefere?", "Qual o preço da calabresa?"),
])
def test_answers_that_must_stay_untouched(answer, message):
    assert strip_unsolicited_offer(answer, message) == answer


def _responder(store, llm=None, settings=None):
    return Responder(settings or Settings(full_context_rewarm_delay_s=0), Encoder(), store, llm or LLM(),
                     InferenceGate(1, 1, 5, 1), full_context=_cache(store))


def _req(n, message="Quanto custa a pizza grande de calabresa?", deadline_ms=44500):
    return RespondRequest(request_id=f"r-test-{n:04d}", tenant_id=BELLA, message=message,
                          options={"deadline_ms": deadline_ms})


def test_concise_tenant_gets_style_rules_and_offer_filter():
    async def scenario():
        store = _store()
        llm = LLM("A pizza grande de calabresa custa R$ 62,90. Quer saber sobre outro sabor ou combo?")
        res = await _responder(store, llm).respond(_req(1, deadline_ms=180000), BELLA, CONCISE)
        assert res.text == "A pizza grande de calabresa custa R$ 62,90."
        assert "ESTILO DE RESPOSTA" in llm.messages[0]["content"]
        standard = dict(CONCISE, response_style="standard")
        res = await _responder(store, LLM(llm.reply)).respond(_req(2, deadline_ms=180000), BELLA, standard)
        assert res.text.endswith("combo?")
    asyncio.run(scenario())


def test_answers_that_leak_missing_data_become_the_standard_unknown_answer():
    async def scenario():
        store = _store()
        for reply in ("A pizza de pepperoni não está listada nos dados da empresa. Posso encaminhar sua dúvida?",
                      "Esse sabor não consta no cardápio."):
            res = await _responder(store, LLM(reply)).respond(_req(1, "Quanto custa a de pepperoni?", 180000), BELLA, CONCISE)
            assert res.text == FALLBACK_TEXT and res.guard == "unknown_normalized"
        ok = await _responder(store, LLM("Não entregamos aos domingos.")).respond(_req(2, "Entregam domingo?", 180000),
                                                                               BELLA, CONCISE)
        assert ok.guard is None
    asyncio.run(scenario())


def test_cold_cost_uses_measured_prefix_and_resident_head():
    async def scenario():
        store = _store()
        responder = _responder(store)
        docs = (await responder.full_context.get(BELLA)).documents
        responder._prefix_tokens[BELLA] = {"head": 600, "full": 1950}
        responder._kv_head = None
        assert responder.cold_prefill_s(BELLA, docs) == pytest.approx((1950 + 150) / 30)
        responder._kv_head = BELLA
        assert responder.cold_prefill_s(BELLA, docs) == pytest.approx((1950 - 600 + 150) / 30)
    asyncio.run(scenario())


class CountingStore:
    def __init__(self, store):
        self.inner, self.top_ks = store, []

    def __getattr__(self, name):
        return getattr(self.inner, name)

    async def search(self, tenant_id, vec, query, top_k, mode, min_score=0.0):
        self.top_ks.append(top_k)
        return await self.inner.search(tenant_id, vec, query, top_k, mode, min_score)


def test_cold_rag_uses_fewer_chunks_only_when_not_even_the_head_is_cached():
    async def scenario():
        store = CountingStore(_store())
        responder = _responder(store)
        responder._prefix_tokens[BELLA] = {"head": 600, "full": 1950}
        res = await responder.respond(_req(1), BELLA, CONCISE)  # nothing resident
        assert res.retrieval.fallback_reason == "kv_cold" and store.top_ks[-1] == 2
        await responder._cancel_rewarm()
        responder._kv_key = None  # head resident after the request, full prefix not
        res = await responder.respond(_req(2), BELLA, CONCISE)
        assert res.retrieval.fallback_reason == "kv_cold" and store.top_ks[-1] == 3
        await responder._cancel_rewarm()
    asyncio.run(scenario())


def test_unloaded_model_means_cold_cache_even_if_the_prefix_was_recorded_warm():
    class UnloadedLLM(LLM):
        async def loaded_models(self):
            return []

    async def scenario():
        store = CountingStore(_store())
        responder = _responder(store, UnloadedLLM())
        await responder.warm_prefix(BELLA, CONCISE)  # prefix recorded as resident
        assert responder._kv_key is not None
        responder._prefix_tokens[BELLA] = {"head": 600, "full": 1950}  # production-sized prefix
        res = await responder.respond(_req(1), BELLA, CONCISE)
        assert res.retrieval.fallback_reason == "kv_cold" and store.top_ks[-1] == 2
        await responder._cancel_rewarm()
    asyncio.run(scenario())


def test_staged_warmup_leaves_the_head_resident_and_schedules_the_full_prefix():
    from app.main import _staged_warmup
    from app.security.auth import TenantRegistry

    async def scenario():
        store = _store()
        responder = _responder(store, settings=Settings(full_context_rewarm_delay_s=0))
        registry = TenantRegistry(tenants={BELLA: CONCISE, "pastelaria_do_ze": {"display_name": "Zé"}})
        await _staged_warmup(responder, registry, [BELLA, "pastelaria_do_ze"], attempts=1, delay_s=0)
        assert responder._kv_head == BELLA and "head" in responder._prefix_tokens[BELLA]
        assert responder._rewarm is not None
        await responder._rewarm
        assert responder._kv_key == responder.prefix_key(responder.s.llm_model, BELLA,
                                                         (await responder.full_context.get(BELLA)).documents, CONCISE)
    asyncio.run(scenario())
