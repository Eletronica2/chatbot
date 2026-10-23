from app.services.conversation_service import ConversationService

FLOW_HOURS = """Nossos horários de funcionamento ⏰

🗓 *Segunda a Quinta:* 18h às 23h
🗓 *Sexta e Sábado:* 18h à 00h
🗓 *Domingo:* 18h às 22h

🛵 *Delivery disponível* todos os dias!
📍 *Retirada no local* — sem taxa de entrega

Tem mais alguma dúvida ou quer fazer um pedido? 😊"""


def test_compose_merges_truncated_ai_reply_with_flow_message():
    ai_reply = "Bom dia! 😊\n\nNossos horários de funcionamento são:\n🗓 *"
    composed = ConversationService._compose_ai_fallback_reply(ai_reply, FLOW_HOURS)
    assert "Bom dia! 😊" in composed
    assert "Segunda a Quinta" in composed
    assert "Domingo" in composed


def test_compose_keeps_complete_ai_reply():
    complete = f"Bom dia!\n\n{FLOW_HOURS}"
    composed = ConversationService._compose_ai_fallback_reply(complete, FLOW_HOURS)
    assert composed == complete


FLOW_WELCOME = """Olá! 👋 Bem-vindo à *Pizzaria Bella Massa*! 🍕

Como posso te ajudar hoje?

1️⃣ Ver cardápio
2️⃣ Fazer pedido
3️⃣ Promoções do dia
4️⃣ Horário de funcionamento"""


def test_compose_does_not_append_greeting_and_menu_to_a_complete_answer():
    answer = "Não tenho essa informação confirmada no momento. Posso encaminhar sua dúvida para a equipe?"
    assert ConversationService._compose_ai_fallback_reply(answer, FLOW_WELCOME) == answer


def test_compose_keeps_a_complete_answer_ending_in_emoji_or_period():
    for answer in ("A pizza de calabresa grande custa R$ 62,90.", "Entregamos sim! 🛵 Qual é o seu bairro?"):
        assert ConversationService._compose_ai_fallback_reply(answer, FLOW_WELCOME) == answer


class _Session:
    def __init__(self, context, assignment_mode="ai", assigned_user_id=None):
        self.context = context
        self.assignment_mode = assignment_mode
        self.assigned_user_id = assigned_user_id


def _pending(reason):
    return {"human_handoff_pending": True, "human_handoff_reason": reason, "human_handoff_at": "x", "messages": []}


def test_successful_ai_reply_clears_a_handoff_raised_by_an_ai_failure():
    for reason in ("local_ai_timeout", "local_ai_unreachable", "gemini_rate_limit", "ai_unavailable"):
        session = _Session(_pending(reason))
        ConversationService._clear_transient_ai_handoff(session)
        assert "human_handoff_pending" not in session.context
        assert session.context["messages"] == []


def test_successful_ai_reply_keeps_human_and_billing_handoffs():
    for reason in ("assumed_by_agent", "transferred", "auto_reply_disabled", "message_limit_reached"):
        session = _Session(_pending(reason))
        ConversationService._clear_transient_ai_handoff(session)
        assert session.context["human_handoff_pending"] is True
    owned = _Session(_pending("local_ai_timeout"), assignment_mode="human", assigned_user_id="3")
    ConversationService._clear_transient_ai_handoff(owned)
    assert owned.context["human_handoff_pending"] is True
