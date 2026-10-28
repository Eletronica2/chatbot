import asyncio
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
        order = {"id": len(self.created) + 1, "order_number": len(self.created) + 1, "total_cents": total,
                 "status": "novo", "status_label": "Novo", **kwargs}
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
        "Novo", "Confirmado", "Em preparo", "Saiu para entrega", "Pronto para retirada", "Entregue", "Retirado",
        "Cancelado",
    }


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
                 "Arthur", "talvez"]


def test_full_delivery_order_requires_explicit_confirmation():
    unconfirmed, _, pending = _converse(DELIVERY_CHAT)
    assert not unconfirmed.orders.created and pending.draft["stage"] == "confirm"
    assistant, replies, result = _converse([*DELIVERY_CHAT, "sim"])
    assert "Anotado" in replies[0] and "2x Calabresa (Grande)" in replies[0]
    assert "Coca-Cola" in replies[1]
    assert "entrega" in replies[2].lower()
    assert "endereço" in replies[3]
    assert replies[4] == "Em qual nome fica o pedido?"
    assert "Total: R$ 132,80" in replies[5] and "SIM" in replies[5]
    assert "SIM" in replies[6]
    assert "Pedido #1 registrado" in replies[7] and len(assistant.orders.created) == 1
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
                              active_flow="f", current_state="boas_vindas", conversation_history=[])

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

    service.tenant_settings_service = SimpleNamespace(get_or_create=get_or_create)
    service.order_assistant = OrderAssistant(FakeCatalog(), FakeOrders())
    service._resolve_session = resolve_session
    service._persist_message = persist_message
    service._persist_session_update = persist_session_update
    service._append_message = lambda *a, **k: None
    service._log_interaction = noop
    service._should_suppress_auto_reply = not_suppressed
    return service, calls, session


def _msg(text):
    return NormalizedMessage(message_id=f"wamid.{abs(hash(text))}", tenant_id="t", phone_number="5534999990000",
                             phone_number_id="pn", display_phone_number="55", message_type=MessageType.TEXT,
                             content=text, timestamp=datetime.utcnow())


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
