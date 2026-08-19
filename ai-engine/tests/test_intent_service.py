from app.services.intent_service import IntentService


def test_bare_pedido_is_not_status_intent():
    service = IntentService()
    assert service.classify("pedido").intent != "pedido_status"
    assert service.classify("fazer pedido").intent != "pedido_status"


def test_status_phrases_still_map_to_pedido_status():
    service = IntentService()
    assert service.classify("status do pedido").intent == "pedido_status"
    assert service.classify("meu pedido").intent == "pedido_status"
    assert service.classify("acompanhar pedido").intent == "pedido_status"
