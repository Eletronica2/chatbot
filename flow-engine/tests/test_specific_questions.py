import pytest

from app.domain.flow import FlowState, GlobalTransition
from app.services.question_router import is_specific_question
from tests.test_flow_runner import _pizzaria_like_flow, _request, _run


def _opted_in_flow():
    definition = _pizzaria_like_flow()
    definition.prefer_ai_for_specific_questions = True
    definition.states["boas_vindas"].transitions.append(
        type(definition.states["boas_vindas"].transitions[0])(condition="contains:pizza", target_state="cardapio_principal"))
    definition.states["atendente_humano"] = FlowState(state="atendente_humano", message="Chamando atendente",
                                                      requires_handoff=True)
    definition.global_transitions.append(GlobalTransition(condition="contains:atendente", target_state="atendente_humano"))
    return definition


def _norm(text):
    from app.services.flow_runner import FlowRunner
    return FlowRunner()._normalize_text(text)


@pytest.mark.parametrize("text", [
    "Quanto custa a pizza de calabresa?",
    "Vocês têm pizza grande?",
    "Qual o preço da calabresa?",
    "Quanto custa uma pizza de frango?",
    "Vocês oferecem Wi-Fi?",
    "Aceita PIX?",
])
def test_specific_questions_are_detected(text):
    assert is_specific_question(_norm(text))


@pytest.mark.parametrize("text", [
    "Quero ver o cardápio.",
    "Me manda o cardápio?",
    "Qual o horário?",
    "Tem promoção hoje?",
    "Tem pizza?",
    "cardapio",
    "1",
    "oi",
    "Calabresa",
])
def test_navigation_and_generic_messages_are_not_specific(text):
    assert not is_specific_question(_norm(text))


def test_flow_specific_generic_terms_extend_the_list():
    assert is_specific_question(_norm("Tem rodízio?"))
    assert not is_specific_question(_norm("Tem rodízio?"), ["rodizio"])


@pytest.mark.parametrize("text", [
    "Quanto custa a pizza de calabresa?",
    "Vocês têm pizza grande?",
    "Quanto custa uma pizza de frango?",
])
def test_opted_in_flow_sends_specific_questions_to_ai_instead_of_the_menu(text):
    result = _run(_opted_in_flow(), _request(text, state="boas_vindas"))
    assert result.requires_ai_fallback is True
    assert result.metadata["routing"] == "specific_question"
    assert result.metadata["state"] == "boas_vindas"


def test_opted_in_flow_answers_a_specific_first_message_instead_of_greeting():
    result = _run(_opted_in_flow(), _request("Quanto custa a pizza de calabresa?"))
    assert result.requires_ai_fallback is True


def test_opted_in_flow_keeps_deterministic_navigation():
    flow = _opted_in_flow()
    menu = _run(flow, _request("Quero ver o cardápio.", state="boas_vindas"))
    assert menu.metadata["state"] == "cardapio_principal" and menu.requires_ai_fallback is False
    generic = _run(flow, _request("Tem pizza?", state="boas_vindas"))
    assert generic.metadata["state"] == "cardapio_principal" and generic.requires_ai_fallback is False
    hours = _run(flow, _request("Qual o horário?", state="boas_vindas"))
    assert hours.metadata["state"] == "horario_funcionamento" and hours.requires_ai_fallback is False


def test_opted_in_flow_keeps_handoff_and_collect_states():
    flow = _opted_in_flow()
    handoff = _run(flow, _request("Posso falar com um atendente?", state="boas_vindas"))
    assert handoff.metadata["state"] == "atendente_humano" and handoff.requires_ai_fallback is False
    collecting = _run(flow, _request("Quanto custa a calabresa grande?", state="iniciar_pedido"))
    assert collecting.metadata["state"] == "pedido_tamanho" and collecting.requires_ai_fallback is False


def test_flows_without_the_option_are_unchanged():
    result = _run(_pizzaria_like_flow(), _request("Quanto custa o cardapio de calabresa?", state="boas_vindas"))
    assert result.metadata["state"] == "cardapio_principal" and result.requires_ai_fallback is False
