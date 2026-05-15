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
