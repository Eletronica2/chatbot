"""Bella Massa flow: menu navigation and the Orders module gate (P0 regression of 2026-10-27)."""
from pathlib import Path

import pytest
import yaml

from app.domain.flow import FlowExecutionRequest
from app.services.business_hours import apply_contextual_cta
from app.services.flow_loader import FlowLoader
from tests.test_flow_runner import _run

BELLA = Path(__file__).resolve().parents[1] / "app/flows/tenants/pizzaria_bella_massa/atendimento_pizzaria_delivery.yaml"
LEGACY = {"pedido_tamanho", "pedido_sabores", "pedido_bebida", "pedido_tipo_entrega", "pedido_endereco",
          "pedido_pagamento", "pedido_confirmacao", "consultar_pedido", "consultar_pedido_resultado"}
ON, OFF = ["orders"], []


def _bella():
    return FlowLoader(BELLA.parents[3])._parse_flow(BELLA, yaml.safe_load(BELLA.read_text(encoding="utf-8")))


FLOW = _bella()


def _say(text, state=None, modules=OFF):
    session_state = {}
    if state:
        session_state = {"current_state": state, "last_state": state, "active_flow": FLOW.name}
    return _run(FLOW, FlowExecutionRequest(tenant_id="pizzaria_bella_massa", message={"content": text, "text": text},
                                           session_state=session_state, enabled_modules=modules))


def _conversation(texts, modules):
    state, responses = None, []
    for text in texts:
        response = _say(text, state, modules)
        responses.append(response)
        state = response.session_state.get("current_state") or state
    return responses


@pytest.mark.parametrize("modules", [ON, OFF])
def test_scenario_a_greeting_menu_then_category_lists_pizzas(modules):
    *_, menu, category = _conversation(["Boa noite", "Cardápio", "Tradicionais"], modules)
    assert menu.metadata["state"] == "cardapio_principal"
    assert category.metadata["state"] == "pizzas_tradicionais" and "Calabresa" in category.reply_text


@pytest.mark.parametrize("modules", [ON, OFF])
@pytest.mark.parametrize("text,expected", [
    ("Quero ver as tradicionais", "pizzas_tradicionais"),
    ("Tradicionais", "pizzas_tradicionais"),
    ("Especiais", "pizzas_especiais"),
    ("quero ver as especiais", "pizzas_especiais"),
    ("Doces", "pizzas_doces"),
    ("Bebidas", "bebidas"),
])
def test_scenario_b_category_requests_never_start_an_order(modules, text, expected):
    response = _say(text, "cardapio_principal", modules)
    assert response.metadata["state"] == expected
    assert response.metadata.get("hook", {}).get("action") != "start_order"


@pytest.mark.parametrize("modules", [ON, OFF])
@pytest.mark.parametrize("state", ["pizzas_tradicionais", "pizzas_especiais", "pizzas_doces", "bebidas",
                                   "promocoes_do_dia", "horario_funcionamento", "boas_vindas"])
def test_browsing_with_quero_moves_between_categories(modules, state):
    assert _say("quero ver as doces", state, modules).metadata["state"] == "pizzas_doces"
    assert _say("Quero ver as tradicionais", state, modules).metadata["state"] == "pizzas_tradicionais"
    assert _say("especiais", state, modules).metadata["state"] == "pizzas_especiais"
    assert _say("quero ver o cardápio", state, modules).metadata["state"] == "cardapio_principal"


def test_orders_off_hides_ordering_and_never_enters_order_states():
    for state in ["boas_vindas", "cardapio_principal", "pizzas_tradicionais", "bebidas", "promocoes_do_dia",
                  "horario_funcionamento"]:
        for text in ["Fazer pedido", "pedido", "quero pedir", "quero fazer um pedido", "combo"]:
            response = _say(text, state, OFF)
            assert response.metadata.get("state") != "iniciar_pedido", (state, text)
    menu = _say("Cardápio", "boas_vindas", OFF)
    assert all("pedido" not in o["value"] for o in menu.metadata["options"])
    assert "fazer seu pedido" not in menu.reply_text
    greeting = _say("Boa noite", None, OFF)
    assert "ajudar com um pedido" not in (greeting.metadata.get("flow_state_message") or greeting.reply_text or "")
    assert all("pedido" not in o["value"] for o in greeting.metadata["options"])
    assert "Quer pedir" not in _say("Tradicionais", "cardapio_principal", OFF).reply_text


def test_orders_on_routes_ordering_to_the_backend_assistant_only():
    for state in ["boas_vindas", "cardapio_principal", "pizzas_tradicionais", "horario_funcionamento"]:
        response = _say("quero fazer um pedido", state, ON)
        assert response.metadata["state"] == "iniciar_pedido", state
        assert response.metadata["hook"] == {"action": "start_order", "return_state": "boas_vindas"}
    assert any(o["value"] == "pedido" for o in _say("Cardápio", "boas_vindas", ON).metadata["options"])


@pytest.mark.parametrize("modules", [ON, OFF])
def test_legacy_order_steps_are_unreachable_from_any_state(modules):
    texts = ["Arthur", "Grande", "Calabresa", "Só a pizza", "Vou retirar", "Rua A, 10", "Cartão", "pix", "dinheiro",
             "entrega", "status", "meu pedido", "consultar", "sim", "ok", "*"]
    for state in FLOW.states:
        for text in texts:
            response = _say(text, state, modules)
            assert response.metadata.get("state") not in LEGACY, (state, text)
            assert "Pedido recebido" not in (response.reply_text or "")


@pytest.mark.parametrize("modules", [ON, OFF])
def test_session_parked_in_legacy_step_restarts_safely(modules):
    response = _say("Cartão", "pedido_pagamento", modules)
    assert response.metadata.get("state") not in LEGACY and "Pedido recebido" not in (response.reply_text or "")
    assert _say("Cardápio", "pedido_confirmacao", modules).metadata["state"] == "cardapio_principal"


def test_price_question_is_not_an_order():
    for modules in (ON, OFF):
        response = _say("Quanto custa a calabresa?", "cardapio_principal", modules)
        assert response.requires_ai_fallback and response.metadata.get("state") != "iniciar_pedido"


def test_cta_placeholder_respects_ordering():
    always_open = {"timezone": "UTC", "schedule": {d: {"open": "00:00", "close": "23:59"} for d in
                   ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]}}
    assert "pedido" in apply_contextual_cta("{cta_pedido}", always_open, ordering=True)
    assert "pedido" not in apply_contextual_cta("{cta_pedido}", always_open, ordering=False)


def test_knowledge_section_still_loads():
    data = yaml.safe_load(BELLA.read_text(encoding="utf-8"))
    assert len(data["knowledge"]["documents"]) == 8
