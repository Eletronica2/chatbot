import asyncio

from app.domain.flow import (
    FlowDefinition,
    FlowExecutionRequest,
    FlowState,
    FlowTransition,
    GlobalTransition,
)
from app.services.flow_runner import FlowRunner


def _pizzaria_like_flow() -> FlowDefinition:
    return FlowDefinition(
        name="atendimento_pizzaria_delivery",
        start_state="boas_vindas",
        fallback_ai=True,
        global_transitions=[
            GlobalTransition(condition="contains:abre", target_state="horario_funcionamento"),
            GlobalTransition(condition="contains:horario", target_state="horario_funcionamento"),
        ],
        intent_aliases={
            "consultar": [
                "consultar pedido",
                "meu pedido",
                "status",
                "cade meu pedido",
            ],
            "horario": ["horario", "abre", "funciona"],
        },
        states={
            "boas_vindas": FlowState(
                state="boas_vindas",
                message="Oi, bem-vindo!",
                fallback_ai=True,
                transitions=[
                    FlowTransition(condition="contains:cardapio", target_state="cardapio_principal"),
                    FlowTransition(condition="contains:pedido", target_state="iniciar_pedido"),
                ],
            ),
            "cardapio_principal": FlowState(
                state="cardapio_principal",
                message="Cardapio aqui",
                fallback_ai=True,
                transitions=[
                    FlowTransition(condition="contains:pedido", target_state="iniciar_pedido"),
                ],
            ),
            "iniciar_pedido": FlowState(
                state="iniciar_pedido",
                message="Qual o seu nome?",
                collect="customer_name",
                transitions=[
                    FlowTransition(condition="*", target_state="pedido_tamanho"),
                ],
            ),
            "pedido_tamanho": FlowState(
                state="pedido_tamanho",
                message="Qual tamanho?",
                collect="pizza_size",
                transitions=[
                    FlowTransition(condition="*", target_state="pedido_sabores"),
                ],
            ),
            "pedido_sabores": FlowState(
                state="pedido_sabores",
                message="Quais sabores?",
                collect="pizza_flavors",
                transitions=[
                    FlowTransition(condition="contains:cardapio", target_state="cardapio_principal"),
                    FlowTransition(condition="*", target_state="pedido_bebida"),
                ],
            ),
            "pedido_bebida": FlowState(
                state="pedido_bebida",
                message="Quer bebida?",
                collect="drink",
            ),
            "consultar_pedido": FlowState(
                state="consultar_pedido",
                message="Me passa o numero do pedido",
                intent_triggers=["consultar"],
                fallback_ai=True,
            ),
            "horario_funcionamento": FlowState(
                state="horario_funcionamento",
                message="Horarios da pizzaria",
                intent_triggers=["horario"],
                fallback_ai=True,
            ),
        },
    )


def _request(
    text: str,
    *,
    state: str | None = None,
    intent: str | None = None,
    collected: dict | None = None,
) -> FlowExecutionRequest:
    session_state = {}
    if state:
        session_state["current_state"] = state
        session_state["last_state"] = state
        session_state["active_flow"] = "atendimento_pizzaria_delivery"
    if collected:
        session_state["collected_data"] = collected
    message = {"content": text, "text": text}
    if intent:
        message["metadata"] = {"detected_intent": intent}
    return FlowExecutionRequest(
        tenant_id="pizzaria_bella_massa",
        phone_number="sim-test",
        message=message,
        session_state=session_state,
    )


def _run(definition: FlowDefinition, request: FlowExecutionRequest):
    return asyncio.run(FlowRunner().run(definition, request))


def test_pedido_from_cardapio_starts_order_not_status_lookup():
    definition = _pizzaria_like_flow()
    result = _run(
        definition,
        _request("pedido", state="cardapio_principal", intent="pedido_status"),
    )
    assert result.metadata.get("state") == "iniciar_pedido"
    assert result.metadata.get("resolution_reason") == "transition_match"
    assert result.requires_ai_fallback is False
    assert result.reply_text


def test_status_phrase_still_jumps_to_consultar():
    definition = _pizzaria_like_flow()
    result = _run(
        definition,
        _request("status do meu pedido", state="cardapio_principal", intent="pedido_status"),
    )
    assert result.metadata.get("state") == "consultar_pedido"
    assert result.metadata.get("resolution_reason") == "intent_match"


def test_collect_wildcard_still_advances_and_stores_data():
    definition = _pizzaria_like_flow()
    result = _run(
        definition,
        _request("Joao Teste", state="iniciar_pedido"),
    )
    assert result.metadata.get("state") == "pedido_tamanho"
    assert result.collected_data.get("customer_name") == "joao teste"
    assert result.requires_ai_fallback is False


def test_unmatched_question_uses_ai_fallback_only():
    definition = _pizzaria_like_flow()
    result = _run(
        definition,
        _request("voces aceitam vale refeicao?", state="boas_vindas"),
    )
    assert result.requires_ai_fallback is True
    assert result.reply_text is None
    assert result.metadata.get("resolution_reason") == "fallback_ai"
    assert result.metadata.get("state") == "boas_vindas"


def test_successful_transition_does_not_request_ai():
    definition = _pizzaria_like_flow()
    result = _run(definition, _request("oi"))
    assert result.metadata.get("resolution_reason") == "flow_start"
    assert result.requires_ai_fallback is False
    assert result.handled is True


def test_flavor_calabresa_does_not_match_abre():
    definition = _pizzaria_like_flow()
    result = _run(
        definition,
        _request("calabresa", state="pedido_sabores"),
    )
    assert result.metadata.get("state") == "pedido_bebida"
    assert result.metadata.get("resolution_reason") == "transition_match"
    assert result.collected_data.get("pizza_flavors") == "calabresa"


def test_horario_phrase_still_matches_abre_as_word():
    runner = FlowRunner()
    assert runner._contains_phrase("calabresa", "abre") is False
    assert runner._contains_phrase("que horas abre", "abre") is True
    assert runner._resolve_alias("calabresa", {"horario": ["abre", "horario"]}) is None
    assert runner._resolve_alias("que horas abre", {"horario": ["abre", "horario"]}) == "horario"


def test_alias_pedido_does_not_resolve_to_consultar():
    runner = FlowRunner()
    aliases = {
        "consultar": ["consultar pedido", "meu pedido", "status", "cade meu pedido"],
    }
    assert runner._resolve_alias("pedido", aliases) is None
    assert runner._resolve_alias("status do pedido", aliases) == "consultar"
    assert runner._canonicalize_detected_intent("pedido_status", aliases) is None
    assert runner._canonicalize_detected_intent("horario_atendimento", {"horario": ["horario"]}) == "horario"
