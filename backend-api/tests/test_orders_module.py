import asyncio
import uuid
from datetime import datetime, timedelta

import pytest

from app.domain import orders as order_domain
from app.services.order_assistant import CatalogMatcher, OrderAssistant, detect_start, is_status_query
from app.services.order_service import OrderError, price_items

SIZES = [("Broto", 4290), ("Média", 5290), ("Grande", 6290)]


def _pizza(pid, name, prices, category="Pizzas Tradicionais"):
    return {"id": pid, "name": name, "category_name": category, "available": True, "price_cents": None,
            "variants": [{"name": n, "price_cents": p} for n, p in zip(("Broto", "Média", "Grande"), prices)]}


PRODUCTS = [
    _pizza(1, "Calabresa", (4290, 5290, 6290)),
    _pizza(2, "Mussarela", (3990, 4990, 5990)),
    _pizza(3, "Frango c/ Catupiry", (4690, 5690, 6690)),
    _pizza(4, "Romeu e Julieta", (4490, 5490, 6690), "Pizzas Doces"),
    _pizza(5, "Quatro Queijos Premium", (5990, 7290, 8790), "Pizzas Especiais"),
    {"id": 6, "name": "Refrigerante Lata", "category_name": "Bebidas", "available": True, "price_cents": None,
     "variants": [{"name": "Coca-Cola", "price_cents": 700}, {"name": "Guaraná Antarctica", "price_cents": 700}]},
    {"id": 7, "name": "Refrigerante 2L", "category_name": "Bebidas", "available": True, "price_cents": None,
     "variants": [{"name": "Coca-Cola", "price_cents": 1400}, {"name": "Guaraná Antarctica", "price_cents": 1400}]},
    {"id": 8, "name": "Água Mineral", "category_name": "Bebidas", "available": True, "price_cents": 400, "variants": []},
    {"id": 9, "name": "Água com Gás", "category_name": "Bebidas", "available": True, "price_cents": 500, "variants": []},
    {"id": 10, "name": "Portuguesa", "category_name": "Pizzas Tradicionais", "available": False, "price_cents": 100,
     "variants": []},
]


def _run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


class FakeCatalog:
    async def list_products(self, tenant_key, *, only_available=False):
        return [p for p in PRODUCTS if p["available"] or not only_available]


class FakeOrders:
    def __init__(self):
        self.created = []

    async def create(self, tenant_key, **kwargs):
        priced = price_items(PRODUCTS, kwargs["items"])
        total = sum(i["line_total_cents"] for i in priced)
        existing = next((o for o in self.created if o["idempotency_key"] == kwargs["idempotency_key"]), None)
        if existing:
            return existing
        status = "aguardando_loja" if kwargs.get("fulfillment") == "entrega" else "novo"
        order = {"id": len(self.created) + 1, "order_number": len(self.created) + 1, "total_cents": total,
                 "subtotal_cents": total, "status": status, "status_label": order_domain.STATUS_LABELS[status], **kwargs}
        self.created.append(order)
        return order

    async def latest_for_customer(self, tenant_key, phone):
        return self.created[-1] if self.created else None


def _matcher():
    return CatalogMatcher(PRODUCTS)


# ── status machine ────────────────────────────────────────────────────────────

def test_status_transitions_follow_fulfillment():
    assert order_domain.allowed_next("novo", "entrega") == ["confirmado", "cancelado"]
    assert order_domain.allowed_next("em_preparo", "entrega") == ["saiu_para_entrega", "cancelado"]
    assert order_domain.allowed_next("em_preparo", "retirada") == ["pronto_para_retirada", "cancelado"]
    assert order_domain.can_transition("saiu_para_entrega", "entregue", "entrega")
    assert not order_domain.can_transition("pronto_para_retirada", "entregue", "retirada")
    assert not order_domain.can_transition("novo", "entregue", "entrega")
    for terminal in ("entregue", "retirado", "cancelado"):
        assert order_domain.allowed_next(terminal, "entrega") == []
    assert set(order_domain.STATUS_LABELS.values()) == {
        "Aguardando confirmação da loja", "Aguardando aceite do cliente",
        "Novo", "Confirmado", "Em preparo", "Saiu para entrega", "Pronto para retirada", "Entregue", "Retirado",
        "Cancelado",
    }
    # Fee and customer acceptance only move through their own operations; by hand only cancel.
    assert order_domain.allowed_next("aguardando_loja", "entrega") == ["cancelado"]
    assert order_domain.allowed_next("aguardando_cliente", "entrega") == ["cancelado"]


def test_money_format():
    assert order_domain.money(6290) == "R$ 62,90"
    assert order_domain.money(123456) == "R$ 1.234,56"


# ── pricing comes from the catalog ────────────────────────────────────────────

def test_price_items_uses_catalog_prices_and_rejects_unavailable():
    priced = price_items(PRODUCTS, [{"product_id": 1, "variant_name": "grande", "quantity": 2},
                                    {"product_id": 8, "quantity": 1, "unit_price_cents": 1}])
    assert [(p["unit_price_cents"], p["line_total_cents"]) for p in priced] == [(6290, 12580), (400, 400)]
    with pytest.raises(OrderError):
        price_items(PRODUCTS, [{"product_id": 10, "quantity": 1}])
    with pytest.raises(OrderError):
        price_items(PRODUCTS, [{"product_id": 1, "variant_name": "Gigante", "quantity": 1}])
    with pytest.raises(OrderError):
        price_items(PRODUCTS, [{"product_id": 1, "variant_name": "Grande", "quantity": 0}])


# ── parsing ───────────────────────────────────────────────────────────────────

def _parsed(text):
    items, ambiguous = _matcher().parse(text)
    return [(i.product["name"], i.quantity, i.variant_name) for i in items], [p["name"] for p in ambiguous]


def test_parse_items_quantities_and_variants():
    assert _parsed("quero 2 calabresas grandes e uma mussarela broto")[0] == [
        ("Calabresa", 2, "Grande"), ("Mussarela", 1, "Broto")]
    assert _parsed("uma grande de calabresa e uma broto de mussarela")[0] == [
        ("Calabresa", 1, "Grande"), ("Mussarela", 1, "Broto")]
    assert _parsed("romeu e julieta média")[0] == [("Romeu e Julieta", 1, "Média")]
    assert _parsed("frango com catupiry grande")[0] == [("Frango c/ Catupiry", 1, "Grande")]
    assert _parsed("guaraná 2 litros") == ([("Refrigerante 2L", 1, "Guaraná Antarctica")], [])
    assert _parsed("água com gás")[0] == [("Água com Gás", 1, None)]


def test_partial_item_next_to_exact_match_is_not_dropped():
    assert _parsed("quero 2 calabresas grandes e uma coca lata")[0] == [
        ("Calabresa", 2, "Grande"), ("Refrigerante Lata", 1, "Coca-Cola")]
    items, ambiguous = _parsed("uma calabresa grande e uma coca")
    assert items == [("Calabresa", 1, "Grande")] and set(ambiguous) == {"Refrigerante Lata", "Refrigerante 2L"}
    assert _parsed("romeu e julieta grande")[0] == [("Romeu e Julieta", 1, "Grande")]


def test_ambiguous_leftover_is_asked_after_noting_the_rest():
    _, replies, result = _converse(["quero uma calabresa grande e uma coca"])
    assert "1x Calabresa (Grande)" in replies[0] and "Refrigerante Lata" in replies[0]
    assert result.draft["stage"] == "items"


def test_parse_ambiguous_and_unavailable():
    items, ambiguous = _parsed("uma coca")
    assert items == [] and set(ambiguous) == {"Refrigerante Lata", "Refrigerante 2L"}
    assert _parsed("uma portuguesa grande") == ([], [])


def test_intent_detection():
    m = _matcher()
    assert detect_start("quero fazer um pedido", m)
    assert detect_start("quero uma calabresa grande", m)
    assert not detect_start("quanto custa a calabresa?", m)
    assert not detect_start("quero ver o cardápio", m)
    assert is_status_query("cadê meu pedido?")


# ── conversation ──────────────────────────────────────────────────────────────

def _converse(messages, *, trigger=None, dry_run=False):
    assistant = OrderAssistant(FakeCatalog(), FakeOrders())
    context, replies, result = {}, [], None
    for index, text in enumerate(messages):
        result = _run(assistant.handle(
            tenant_id="t", text=text, context=context, customer_phone="5534999990000", phone_number_id="pn",
            session_id="s", trigger=trigger if index == 0 else None, dry_run=dry_run,
        ))
        replies.append(result.reply if result else None)
        context = {"order_draft": result.draft} if result else context
    return assistant, replies, result


DELIVERY_CHAT = ["quero 2 calabresas grandes", "e uma coca lata", "não", "entrega", "Rua das Flores, 123, Centro",
                 "Uberlândia", "Arthur", "talvez"]


def test_full_delivery_order_requires_explicit_confirmation():
    unconfirmed, _, pending = _converse(DELIVERY_CHAT)
    assert not unconfirmed.orders.created and pending.draft["stage"] == "confirm"
    assistant, replies, result = _converse([*DELIVERY_CHAT, "sim"])
    assert "Anotado" in replies[0] and "2x Calabresa (Grande)" in replies[0]
    assert "Coca-Cola" in replies[1]
    assert "entrega" in replies[2].lower()
    assert "endereço" in replies[3]
    assert replies[4].endswith("Qual é a cidade?")
    assert replies[5] == "Em qual nome fica o pedido?"
    assert "Subtotal dos produtos: R$ 132,80" in replies[6] and "Total final: pendente" in replies[6]
    assert "Taxa de entrega: a confirmar pela loja" in replies[6] and "Total: R$" not in replies[6]
    assert "SIM" in replies[7]
    assert "Pedido #1 recebido e aguardando a confirmação da loja" in replies[8]
    assert "Total final: pendente" in replies[8] and len(assistant.orders.created) == 1
    order = assistant.orders.created[0]
    assert order["fulfillment"] == "entrega" and order["customer_name"] == "Arthur"
    assert order["idempotency_key"].startswith("draft:")
    assert result.draft is None


def test_pickup_flow_from_flow_hook_and_variant_question():
    assistant, replies, result = _converse(["quero", "mussarela", "média", "só isso", "vou retirar", "Ana", "sim"],
                                           trigger={"action": "start_order", "return_state": "boas_vindas"})
    assert "O que você gostaria de pedir" in replies[0]
    assert "Qual opção para Mussarela" in replies[1]
    assert "Total: R$ 49,90" in replies[5] and "Retirada na loja" in replies[5]
    assert assistant.orders.created[0]["fulfillment"] == "retirada"
    assert result.return_state == "boas_vindas"


def test_single_partial_candidate_is_taken():
    _, replies, result = _converse(["quero um guaraná 2 litros"])
    assert "1x Refrigerante 2L (Guaraná Antarctica)" in replies[0]


def test_declining_and_cancel_do_not_create_orders():
    assistant, replies, _ = _converse(["quero uma calabresa grande", "não", "retirada", "Ana", "não"])
    assert "não registrei" in replies[-1] and not assistant.orders.created
    assistant, replies, result = _converse(["quero uma calabresa grande", "cancelar"])
    assert "cancelei" in replies[-1] and result.draft is None and not assistant.orders.created


def test_dry_run_never_creates_orders():
    assistant, replies, _ = _converse(["quero uma calabresa grande", "retirada", "Ana", "sim"], dry_run=True)
    assert "Simulação" in replies[-1] and not assistant.orders.created


def test_handoff_releases_the_message_to_the_flow():
    _, replies, result = _converse(["quero uma calabresa grande", "quero falar com um atendente"])
    assert replies[-1] == "" and result.draft is None


def test_unrelated_messages_are_not_intercepted():
    _, replies, _ = _converse(["qual o horário de funcionamento?"])
    assert replies == [None]


def test_expired_draft_is_ignored():
    assistant = OrderAssistant(FakeCatalog(), FakeOrders())
    old = (datetime.utcnow() - timedelta(hours=3)).isoformat()
    draft = {"id": "x", "stage": "confirm", "items": [{"product_id": 1, "name": "Calabresa", "variant_name": "Grande",
                                                       "quantity": 1}], "fulfillment": "retirada",
             "customer_name": "Ana", "updated_at": old}
    result = _run(assistant.handle(tenant_id="t", text="sim", context={"order_draft": draft},
                                   customer_phone="5534999990000", phone_number_id=None, session_id=None))
    assert result is None and not assistant.orders.created


# ── conversation pipeline integration ─────────────────────────────────────────

from types import SimpleNamespace  # noqa: E402

from fastapi import HTTPException  # noqa: E402

from app.api.routes.tenant_settings import TenantSettingsPatchPayload, assert_tenant_settings_patch_access  # noqa: E402
from app.domain.execution_context import ExecutionContext  # noqa: E402
from app.domain.message import MessageType, NormalizedMessage  # noqa: E402
from app.domain.tenant import TenantSettings  # noqa: E402
from app.services.conversation_service import ConversationService  # noqa: E402
from app.services.flow_knowledge import build_documents  # noqa: E402
from app.services.knowledge_sync_service import catalog_document  # noqa: E402


def _pipeline(orders_enabled: bool):
    service = ConversationService.__new__(ConversationService)
    settings = TenantSettings(tenant_id="t", orders_enabled=orders_enabled)
    calls = {"persisted": [], "updates": []}
    session = SimpleNamespace(session_id="s1", context={}, conversation_state={}, assignment_mode="ai",
                              active_flow="f", current_state="boas_vindas", conversation_history=[],
                              detected_intent=None, phone_number="5534999990000")

    async def get_or_create(tenant_id):
        return settings

    async def resolve_session(message, ctx):
        return session

    async def persist_message(ctx, **kwargs):
        calls["persisted"].append(kwargs)

    async def persist_session_update(ctx, current, **kwargs):
        calls["updates"].append(kwargs)
        if kwargs.get("context_updates"):
            current.context.update(kwargs["context_updates"])
        return current

    async def noop(*args, **kwargs):
        return None

    async def not_suppressed(*args, **kwargs):
        return False

    async def get_session(tenant_id, phone):
        return session

    service.tenant_settings_service = SimpleNamespace(get_or_create=get_or_create)
    service.session_service = SimpleNamespace(repository=SimpleNamespace(get_session=get_session))
    service.order_assistant = OrderAssistant(FakeCatalog(), FakeOrders())
    service._resolve_session = resolve_session
    service._persist_message = persist_message
    service._persist_session_update = persist_session_update
    service._append_message = lambda *a, **k: None
    service._log_interaction = noop
    service._should_suppress_auto_reply = not_suppressed
    return service, calls, session


def _msg(text, message_id=None, timestamp=None):
    return NormalizedMessage(message_id=message_id or f"wamid.{uuid.uuid4().hex}", tenant_id="t",
                             phone_number="5534999990000", phone_number_id="pn", display_phone_number="55",
                             message_type=MessageType.TEXT, content=text, timestamp=timestamp or datetime.utcnow())


def _core(service, text, ctx=None):
    session = _run(service._resolve_session(None, None))
    return _run(service._maybe_order_assistant(_msg(text), session, ctx or ExecutionContext.production(), 0.0))


def test_orders_disabled_never_intercepts():
    service, calls, session = _pipeline(orders_enabled=False)
    assert _core(service, "quero 2 calabresas grandes") is None
    assert calls["persisted"] == [] and "order_draft" not in session.context


def test_orders_enabled_purchase_intent_is_owned_by_assistant():
    service, calls, session = _pipeline(orders_enabled=True)
    action = _core(service, "quero 2 calabresas grandes")
    assert action.source == "order_assistant" and "2x Calabresa (Grande)" in action.reply_text
    assert session.context["order_draft"]["stage"] == "more"
    assert calls["persisted"][0]["source"] == "order_assistant"


def test_orders_enabled_unrelated_message_falls_through():
    service, calls, _ = _pipeline(orders_enabled=True)
    assert _core(service, "qual o horário?") is None and calls["persisted"] == []


def test_dry_run_context_never_creates_orders_in_pipeline():
    service, _, session = _pipeline(orders_enabled=True)
    ctx = ExecutionContext.dry_run()
    for text in ["quero uma calabresa grande", "retirada", "Ana", "sim"]:
        action = _run(service._maybe_order_assistant(_msg(text), session, ctx, 0.0))
    assert "Simulação" in action.reply_text and not service.order_assistant.orders.created


def test_only_tenant_admin_toggles_orders():
    payload = TenantSettingsPatchPayload(orders_enabled=True)
    with pytest.raises(HTTPException) as exc:
        assert_tenant_settings_patch_access(SimpleNamespace(role="agent", tenant_id="t"), payload)
    assert exc.value.status_code == 403
    assert_tenant_settings_patch_access(SimpleNamespace(role="owner", tenant_id="t"), payload)
    assert_tenant_settings_patch_access(SimpleNamespace(role="superadmin", tenant_id="default"), payload)
    assert TenantSettings(tenant_id="x").orders_enabled is False


def test_agent_capabilities_view_and_update_orders_but_not_catalog():
    from app.api.access import capabilities_for
    agent = capabilities_for(SimpleNamespace(role="agent", tenant_id="t"))
    owner = capabilities_for(SimpleNamespace(role="owner", tenant_id="t"))
    assert agent["canViewOrders"] and agent["canUpdateOrders"] and not agent["canManageCatalog"]
    assert owner["canManageCatalog"]


# ── knowledge ─────────────────────────────────────────────────────────────────

FLOW_YAML = """
name: f
start_state: a
states:
  a:
    message: |
      Nossas pizzas 🍕
      • *Calabresa* — R$ 42,90 / R$ 52,90
      Quer pedir alguma dessas?
knowledge:
  price_columns: [broto, grande]
  retire: [antigo]
  documents:
    - id: doc-pizzas
      title: Pizzas
      states: [a]
      append: "Tamanhos: broto e grande."
"""


def test_flow_knowledge_is_built_from_states():
    docs, retired = build_documents(FLOW_YAML)
    assert retired == ["antigo"]
    assert docs[0]["content"] == "# Pizzas\n\nNossas pizzas\n- Calabresa: broto R$ 42,90, grande R$ 52,90\n\nTamanhos: broto e grande.\n"
    assert build_documents("name: f\nstart_state: a\nstates: {a: {message: oi}}\n") == ([], [])


def test_catalog_document_lists_prices_and_unavailable():
    doc = catalog_document("Bella", PRODUCTS)
    assert "- Calabresa: Broto R$ 42,90, Média R$ 52,90, Grande R$ 62,90" in doc["content"]
    assert "Indisponíveis no momento: Portuguesa." in doc["content"]


# ── P0 2026-10-27: no order without explicit, current confirmation ────────────

from app.domain.message import FlowExecutionResult  # noqa: E402
from app.services.order_assistant import claims_order_confirmation, price_reply  # noqa: E402

SUMMARY_CHAT = ["quero duas pizzas grandes de calabresa", "não", "retirada", "Ana"]


def _assistant_until_summary(orders=None):
    assistant = OrderAssistant(FakeCatalog(), orders or FakeOrders())
    context, result = {}, None
    for text in SUMMARY_CHAT:
        result = _run(assistant.handle(tenant_id="t", text=text, context=context, customer_phone="5534999990000",
                                       phone_number_id="pn", session_id="s", message_id=f"m-{text}"))
        context = {"order_draft": result.draft}
    return assistant, context, result


def _say(assistant, context, text, *, now=None, message_ts=None, message_id=None):
    return _run(assistant.handle(tenant_id="t", text=text, context=context, customer_phone="5534999990000",
                                 phone_number_id="pn", session_id="s", now=now, message_ts=message_ts,
                                 message_id=message_id or f"m-{uuid.uuid4().hex}"))


def test_scenario_d_purchase_intent_collects_data_and_waits_for_confirmation():
    assistant, context, result = _assistant_until_summary()
    assert "2x Calabresa (Grande)" in result.reply and "Total: R$ 125,80" in result.reply and "SIM" in result.reply
    assert result.draft["stage"] == "confirm" and not assistant.orders.created


def test_scenario_e_silence_never_creates_and_old_confirmation_is_rechecked():
    assistant, context, _ = _assistant_until_summary()
    later = datetime.utcnow() + timedelta(minutes=3)
    assert not assistant.orders.created  # three minutes of silence: nothing runs on its own
    reply = _say(assistant, context, "oi", now=later)
    assert "SIM" in reply.reply and not assistant.orders.created
    expired = _say(assistant, context, "sim", now=datetime.utcnow() + timedelta(minutes=20))
    assert "Confira" in expired.reply and not assistant.orders.created
    assert expired.draft["stage"] == "confirm"


def test_scenario_f_explicit_confirmation_creates_exactly_one_order():
    assistant, context, _ = _assistant_until_summary()
    result = _say(assistant, context, "Sim, confirmo")
    assert "Pedido #1 registrado" in result.reply and len(assistant.orders.created) == 1
    assert result.draft is None


@pytest.mark.parametrize("text", ["pode", "isso", "s", "ok", "sim, mas quero trocar a pizza", "talvez", "beleza"])
def test_ambiguous_replies_never_confirm(text):
    assistant, context, _ = _assistant_until_summary()
    _say(assistant, context, text)
    assert not assistant.orders.created


def test_scenario_g_duplicate_webhook_and_late_events():
    assistant, context, _ = _assistant_until_summary()
    first = _say(assistant, context, "sim", message_id="wamid.dup")
    assert len(assistant.orders.created) == 1
    replay = _say(assistant, {"order_draft": {**context["order_draft"], "seen_message_ids": ["wamid.dup"]}}, "sim",
                  message_id="wamid.dup")
    assert replay.ignore and len(assistant.orders.created) == 1
    assert _say(assistant, {"order_draft": first.draft}, "sim") is None  # no draft: a stray "sim" starts nothing
    late_ts = datetime.utcnow() - timedelta(seconds=40)
    assistant2, context2, _ = _assistant_until_summary()
    stale = _say(assistant2, context2, "sim", message_ts=late_ts)
    assert "anterior ao resumo" in stale.reply and not assistant2.orders.created


def test_confirmation_is_bound_to_the_current_summary_prices():
    assistant, context, _ = _assistant_until_summary()
    PRODUCTS[0]["variants"][2]["price_cents"] = 6990
    try:
        changed = _say(assistant, context, "sim")
    finally:
        PRODUCTS[0]["variants"][2]["price_cents"] = 6290
    assert "mudaram" in changed.reply and "R$ 139,80" in changed.reply and not assistant.orders.created


class FailingOrders(FakeOrders):
    async def create(self, tenant_key, **kwargs):
        raise RuntimeError("database down")


class RejectingOrders(FakeOrders):
    async def create(self, tenant_key, **kwargs):
        raise OrderError("o módulo Pedidos está desativado para esta empresa")


@pytest.mark.parametrize("orders", [FailingOrders, RejectingOrders])
def test_scenario_h_failed_persistence_never_reports_success(orders):
    assistant, context, _ = _assistant_until_summary(orders())
    result = _say(assistant, context, "sim")
    assert "registrado!" not in result.reply and "não" in result.reply.lower()
    assert not assistant.orders.created


def test_browsing_and_price_questions_never_start_an_order():
    matcher = _matcher()
    for text in ["quero ver a calabresa", "quero ver as tradicionais", "Quanto custa a calabresa?",
                 "quanto custa a calabresa grande", "quero saber o preço da calabresa"]:
        assert not detect_start(text, matcher), text


def test_scenario_c_price_comes_from_the_catalog():
    reply = _run(price_reply(FakeCatalog(), "t", "Quanto custa a calabresa?"))
    assert "Calabresa" in reply and "Grande R$ 62,90" in reply
    assert _run(price_reply(FakeCatalog(), "t", "qual o horário?")) is None
    assert _run(price_reply(FakeCatalog(), "t", "quanto custa a pizza de abacaxi?")) is None


def test_order_claims_are_detected():
    assert claims_order_confirmation("🎉 Pedido recebido com sucesso!")
    assert claims_order_confirmation("Prontinho, seu pedido foi confirmado e já vai sair")
    assert claims_order_confirmation("Anotei seu pedido!")
    assert not claims_order_confirmation("Posso te ajudar a montar seu pedido?")
    assert not claims_order_confirmation("A calabresa grande custa R$ 62,90")


def _core_pipeline(orders_enabled, flow_result, ai_reply="Oi!"):
    service, calls, session = _pipeline(orders_enabled)
    seen = {}

    async def detect_intent(**kwargs):
        from app.services.ai_service import IntentDetectionResult
        return IntentDetectionResult(intent=None, confidence=0.0)

    async def execute_flow(message, current, enabled_modules=None):
        seen["modules"] = enabled_modules
        return flow_result

    async def generate_response(*args, **kwargs):
        from app.domain.message import AIResponse
        return AIResponse(reply_text=ai_reply, handled=True, metadata={})

    async def no(*args, **kwargs):
        return False

    async def same(current):
        return current

    async def no_usage(*args, **kwargs):
        return None

    service.billing_gate = SimpleNamespace(enabled=True)
    service.message_service = SimpleNamespace(was_processed=no)
    service.ai_service = SimpleNamespace(detect_intent=detect_intent, generate_response=generate_response)
    service.flow_service = SimpleNamespace(execute_flow=execute_flow)
    service._ensure_operational_defaults = same
    service._record_ai_usage = no_usage
    return service, calls, seen


def _flow(state, hook=None, reply="Ótimo, vamos lá! Pra começar: qual é o seu nome?", **extra):
    return FlowExecutionResult(handled=True, reply_text=reply, metadata={"state": state, "hook": hook or {}},
                               session_state={"current_state": state}, **extra)


def _handle(service, text):
    return _run(service._handle_incoming_core(_msg(text), execution_context=ExecutionContext.production()))


def test_orders_off_blocks_legacy_start_and_confirmation_even_from_old_flows():
    for hook in ({"action": "start_order"}, {"action": "confirmar_pedido"}):
        service, calls, seen = _core_pipeline(False, _flow("x", hook, reply="🎉 Pedido recebido com sucesso!"))
        action = _handle(service, "Cartão")
        assert seen["modules"] == []
        assert action.source == "order_blocked" and "Pedido recebido" not in action.reply_text
        assert not service.order_assistant.orders.created


def test_orders_on_start_order_goes_to_the_assistant_never_the_legacy_text():
    service, calls, seen = _core_pipeline(True, _flow("iniciar_pedido", {"action": "start_order"}))
    action = _handle(service, "pedido")
    assert seen["modules"] == ["orders"]
    assert action.source == "order_assistant" and "qual é o seu nome" not in action.reply_text


def test_orders_on_but_assistant_unavailable_sends_no_legacy_step():
    service, calls, _ = _core_pipeline(True, _flow("iniciar_pedido", {"action": "start_order"}))
    service.order_assistant = None
    action = _handle(service, "quero fazer um pedido")
    assert action.source == "order_blocked" and action.requires_handoff


def test_orders_on_legacy_confirmation_is_still_blocked():
    service, _, _ = _core_pipeline(True, _flow("pedido_confirmacao", {"action": "confirmar_pedido"},
                                               reply="🎉 Pedido recebido com sucesso!"))
    action = _handle(service, "Cartão")
    assert action.source == "order_blocked" and not service.order_assistant.orders.created


@pytest.mark.parametrize("enabled", [True, False])
def test_flow_text_confirming_an_order_is_never_sent(enabled):
    flow = _flow("etapa_editada_no_painel", reply="🎉 Pedido recebido com sucesso!\nNossa equipe já vai conferir tudo",
                 requires_handoff=True)
    service, _, _ = _core_pipeline(enabled, flow)
    action = _handle(service, "Cartão")
    assert action.source == "order_blocked" and "Pedido recebido" not in action.reply_text


@pytest.mark.parametrize("enabled", [True, False])
def test_ai_reply_claiming_an_order_is_replaced(enabled):
    fallback = FlowExecutionResult(handled=True, reply_text=None, requires_ai_fallback=True,
                                   metadata={"state": "cardapio_principal"}, session_state={})
    service, _, _ = _core_pipeline(enabled, fallback, ai_reply="Seu pedido foi confirmado! Chega em 40 min.")
    action = _handle(service, "pode mandar")
    assert "confirmado" not in action.reply_text and not service.order_assistant.orders.created


@pytest.mark.parametrize("enabled", [True, False])
def test_price_question_answered_from_catalog_in_both_modes(enabled):
    service, _, seen = _core_pipeline(enabled, _flow("cardapio_principal"))
    action = _handle(service, "Quanto custa a calabresa?")
    assert action.source == "catalog_price" and "R$ 62,90" in action.reply_text
    assert "modules" not in seen and not service.order_assistant.orders.created


@pytest.mark.parametrize("enabled", [True, False])
def test_category_navigation_reaches_the_flow_in_both_modes(enabled):
    service, _, seen = _core_pipeline(enabled, _flow("pizzas_tradicionais", reply="Nossas Pizzas Tradicionais"))
    action = _handle(service, "Quero ver as tradicionais")
    assert action.source == "flow" and action.reply_text == "Nossas Pizzas Tradicionais"
    assert not service.order_assistant.orders.created


# ── P0 2026-10-27 23:46: greeting answered with an invented order (stale history/state) ──

from app.domain.session import ConversationSession, SessionMessage  # noqa: E402

OLD = datetime.utcnow() - timedelta(hours=1)
LEGACY_TURNS = [("user", "Vou retirar no local"), ("assistant", "Quase lá! Como você vai pagar?"), ("user", "Cartão"),
                ("assistant", "🎉 Pedido recebido com sucesso!")]
LEGACY_COLLECTED = {"payment_method": "cartao", "address": "vou retirar no local", "pizza_size": "grande"}


def _real_session(last_interaction, *, turns=LEGACY_TURNS, state="pizzas_tradicionais", collected=None):
    session = ConversationSession(tenant_id="t", phone_number="5534999990000", current_state=state,
                                  active_flow="f", last_interaction=last_interaction,
                                  conversation_state={"current_state": state, "collected_data": dict(collected or {})})
    for role, content in turns:
        session.conversation_history.append(SessionMessage(role=role, content=content, created_at=last_interaction))
    session.context = {"messages": [{"role": m.role, "content": m.content, "created_at": m.created_at.isoformat(),
                                     "source": m.source} for m in session.conversation_history]}
    return session


def _greeting_pipeline(session, orders_enabled):
    seen = {}
    fallback = FlowExecutionResult(handled=True, reply_text=None, requires_ai_fallback=True,
                                   metadata={"state": "boas_vindas"}, session_state={}, collected_data={})
    service, _, _ = _core_pipeline(orders_enabled, fallback, ai_reply="Boa noite! Como posso ajudar?")

    async def resolve(message, ctx):
        return session

    async def execute_flow(message, current, enabled_modules=None):
        seen["flow_state"] = dict(current.conversation_state)
        seen["flow_current"] = current.current_state
        return fallback

    async def generate_response(message, ai_session, **kwargs):
        from app.domain.message import AIResponse
        seen["ai_messages"] = [m["content"] for m in ai_session.context.get("messages") or []]
        return AIResponse(reply_text="Boa noite! Como posso ajudar?", handled=True, metadata={})

    async def persist_session_update(ctx, current, **kwargs):
        return current

    async def get_session(tenant_id, phone):
        return session

    service._resolve_session = resolve
    service._persist_session_update = persist_session_update
    service._append_message = ConversationService._append_message.__get__(service)
    service.session_service = SimpleNamespace(repository=SimpleNamespace(get_session=get_session))
    service.flow_service = SimpleNamespace(execute_flow=execute_flow)
    service.ai_service = SimpleNamespace(detect_intent=service.ai_service.detect_intent,
                                         generate_response=generate_response)
    return service, seen


@pytest.mark.parametrize("enabled", [True, False])
def test_greeting_after_old_conversation_starts_a_clean_episode(enabled):
    session = _real_session(OLD, collected=LEGACY_COLLECTED)
    session.last_interaction = datetime.utcnow()  # housekeeping saves refresh this; the turns' dates decide
    service, seen = _greeting_pipeline(session, enabled)
    action = _handle(service, "Boa noite")
    assert seen["flow_state"].get("collected_data") in (None, {}) and seen["flow_current"] is None
    assert seen["ai_messages"] == ["Boa noite"]  # nothing from the old conversation reaches the AI
    assert "pedido" not in action.reply_text.lower()
    assert [m.content for m in session.conversation_history][:4] == [c for _, c in LEGACY_TURNS]  # history kept


def test_consecutive_messages_keep_their_episode_context():
    recent = datetime.utcnow() - timedelta(minutes=2)
    session = _real_session(recent, turns=[("user", "Cardápio"), ("assistant", "Aqui está nosso cardápio")],
                            state="cardapio_principal")
    session.context["episode_started_at"] = (recent - timedelta(seconds=1)).isoformat()
    service, seen = _greeting_pipeline(session, True)
    _handle(service, "e as bebidas?")
    assert seen["flow_current"] == "cardapio_principal"
    assert seen["ai_messages"] == ["Cardápio", "Aqui está nosso cardápio", "e as bebidas?"]


@pytest.mark.parametrize("finished", ["Pedido #1 registrado! ✅", "Tudo bem, cancelei este pedido."])
def test_new_service_after_completed_or_cancelled_order_never_sees_order_turns(finished):
    recent = datetime.utcnow() - timedelta(minutes=5)
    session = _real_session(recent, turns=[], state="bebidas")
    session.context["episode_started_at"] = (recent - timedelta(minutes=5)).isoformat()
    for role, content, source in [("user", "Quero duas calabresas", "order_assistant"),
                                  ("assistant", "Confira seu pedido", "order_assistant"),
                                  ("user", "sim", "order_assistant"), ("assistant", finished, "order_assistant")]:
        session.conversation_history.append(SessionMessage(role=role, content=content, created_at=recent, source=source))
        session.context["messages"].append({"role": role, "content": content, "created_at": recent.isoformat(),
                                            "source": source})
    service, seen = _greeting_pipeline(session, True)
    _handle(service, "Boa noite")
    assert seen["ai_messages"] == ["Boa noite"]
    old = _real_session(OLD, turns=[("assistant", finished)], state="bebidas")
    service, seen = _greeting_pipeline(old, True)
    _handle(service, "Boa noite")
    assert seen["ai_messages"] == ["Boa noite"] and seen["flow_current"] is None


def test_order_assistant_turns_are_tagged_and_hidden_from_the_ai():
    service, calls, session = _pipeline(True)
    real = ConversationSession(tenant_id="t", phone_number="5534999990000")
    real.append_history(role="user", content="quero 2 calabresas grandes")
    session.conversation_history = real.conversation_history
    session.append_history = real.append_history
    service._append_message = ConversationService._append_message.__get__(service)
    _core(service, "quero 2 calabresas grandes")
    assert [m.source for m in real.conversation_history] == ["order_assistant", "order_assistant"]
    assert ConversationService._ai_view(session).context["messages"] == []


def test_invented_order_greeting_is_detected():
    assert claims_order_confirmation("Boa noite! 😊 Já temos seu pedido com cartão e será entregue em até 5km.")
    assert claims_order_confirmation("Seu pedido está a caminho!")
    assert claims_order_confirmation("Pagamento confirmado, obrigado!")
    assert not claims_order_confirmation("Para pedidos acima de R$ 80,00 o frete é grátis em até 5km.")
    assert not claims_order_confirmation("Quer fazer um pedido ou ver o cardápio?")


def test_reset_state_endpoint_clears_only_transient_state_and_audits():
    from app.api.routes.conversations import reset_conversation_state

    session = _real_session(OLD, collected=LEGACY_COLLECTED)
    session.context.update({"order_draft": {"id": "x"}, "human_handoff_pending": True})
    audits = []

    async def get_or_create_session(tenant_id, phone):
        return session

    async def update_session(current):
        return current

    async def append(**kwargs):
        audits.append(kwargs)

    owner = SimpleNamespace(role="owner", tenant_id="t", user_id="1", display_name="Dono")
    result = _run(reset_conversation_state(
        "t:5534999990000", user=owner,
        session_service=SimpleNamespace(get_or_create_session=get_or_create_session, update_session=update_session),
        audit=SimpleNamespace(append=append)))
    assert result["cleared"]["collected_keys"] == sorted(LEGACY_COLLECTED)
    assert session.conversation_state == {} and session.current_state is None
    assert "order_draft" not in session.context and "human_handoff_pending" not in session.context
    assert len(session.conversation_history) == 4 and audits[0]["action"] == "conversation.reset_state"
    with pytest.raises(HTTPException):
        _run(reset_conversation_state("t:5534999990000", user=SimpleNamespace(role="agent", tenant_id="t"),
                                      session_service=None, audit=None))
