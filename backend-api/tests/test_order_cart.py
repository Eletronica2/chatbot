"""Order #2 (Bella Massa, 28/10/2026) regressions: quantities, cart operations, address and pending delivery fee."""
import asyncio
from datetime import datetime, timedelta

import pytest

from app.domain import orders as order_domain
from app.services.order_assistant import CatalogMatcher, OrderAssistant, parse_address
from app.services.order_service import OrderConflict, price_items

SIZES = ("Broto", "Média", "Grande")


def _pizza(pid, name, prices):
    return {"id": pid, "name": name, "available": True, "price_cents": None, "category_name": "Pizzas",
            "variants": [{"name": n, "price_cents": p} for n, p in zip(SIZES, prices)]}


def _drink(pid, name, price, flavors):
    return {"id": pid, "name": name, "available": True, "price_cents": None, "category_name": "Bebidas",
            "variants": [{"name": f, "price_cents": price} for f in flavors]}


BELLA = [
    _pizza(1, "Mussarela", (3990, 4990, 5990)),
    _pizza(2, "Calabresa", (4290, 5290, 6290)),
    _pizza(3, "Quatro Queijos Premium", (5990, 7290, 8790)),
    _pizza(4, "Prestígio", (4790, 5790, 6990)),
    _drink(5, "Refrigerante Lata", 700, ["Coca-Cola", "Guaraná Antarctica", "Fanta", "Sprite"]),
    _drink(6, "Refrigerante 2L", 1400, ["Coca-Cola", "Guaraná Antarctica", "Fanta"]),
    _drink(7, "Suco Natural", 1000, ["Laranja", "Limão", "Maracujá", "Uva"]),
    {"id": 8, "name": "Água Mineral", "available": True, "price_cents": 400, "variants": [], "category_name": "Bebidas"},
]


def _run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


class Catalog:
    async def list_products(self, tenant_key, *, only_available=False):
        return BELLA


class Orders:
    def __init__(self):
        self.created, self.pending, self.decisions = [], None, []

    async def create(self, tenant_key, **kwargs):
        priced = price_items(BELLA, kwargs["items"])
        subtotal = sum(i["line_total_cents"] for i in priced)
        status = "aguardando_loja" if kwargs["fulfillment"] == "entrega" else "novo"
        order = {"id": len(self.created) + 1, "order_number": len(self.created) + 1, "status": status,
                 "subtotal_cents": subtotal, "total_cents": subtotal, "priced": priced, **kwargs}
        self.created.append(order)
        return order

    async def latest_for_customer(self, tenant_key, phone):
        return None

    async def pending_acceptance(self, tenant_key, phone):
        return self.pending

    async def customer_decision(self, tenant_key, order_id, *, accept, expected_total_cents):
        if expected_total_cents != self.pending["total_cents"]:
            raise OrderConflict("changed")
        self.decisions.append(accept)
        return {**self.pending, "status": "confirmado" if accept else "cancelado"}


class Chat:
    def __init__(self, trigger=None):
        self.assistant = OrderAssistant(Catalog(), Orders())
        self.context, self.trigger, self.result, self.count = {}, trigger, None, 0

    def say(self, text, message_id=None):
        self.count += 1
        result = _run(self.assistant.handle(
            tenant_id="pizzaria_bella_massa", text=text, context=self.context, customer_phone="5534999990000",
            phone_number_id="pn", session_id="s", trigger=self.trigger if self.count == 1 else None,
            message_id=message_id or f"m{self.count}"))
        self.result = result
        if result is not None and not result.ignore:
            self.context = {"order_draft": result.draft}
        return result.reply if result else None

    @property
    def draft(self):
        return self.context.get("order_draft") or {}

    def cart(self):
        return sorted((i["name"], i.get("variant_name"), i["quantity"]) for i in self.draft.get("items", []))


def _parsed(text):
    items, ambiguous = CatalogMatcher(BELLA).parse(text)
    return [(i.product["name"], i.quantity) for i in items], [p["name"] for p in ambiguous]


# 1/2. quantities: numbers inside names, sizes and packaging are not quantities ────────────────

@pytest.mark.parametrize("text,expected", [
    ("Quatro Queijos", [("Quatro Queijos Premium", 1)]),
    ("Pizza 4 Queijos", [("Quatro Queijos Premium", 1)]),
    ("Duas Quatro Queijos", [("Quatro Queijos Premium", 2)]),
    ("Quero 4 pizzas de Quatro Queijos", [("Quatro Queijos Premium", 4)]),
    ("quatro queijos premium", [("Quatro Queijos Premium", 1)]),
    ("Refrigerante 2L", [("Refrigerante 2L", 1)]),
    ("Dois refrigerantes de 2L", [("Refrigerante 2L", 2)]),
    ("2 refrigerantes de 2 litros", [("Refrigerante 2L", 2)]),
    ("uma coca 2 litros", [("Refrigerante 2L", 1)]),
    ("Mussarela, calabresa e quatro queijos", [("Mussarela", 1), ("Calabresa", 1), ("Quatro Queijos Premium", 1)]),
])
def test_quantities_ignore_numbers_in_names_and_packaging(text, expected):
    assert _parsed(text)[0] == expected


def test_quanto_is_not_quatro():
    assert _parsed("quanto custa a pizza de abacaxi?") == ([], [])


# replay of order #2 (original messages from MySQL) ────────────────────────────────────────────

ORDER_2 = ["Pedido", "Mussarela, calabresa e quatro queijos. Quero também uma coca 2 litros. E uma de prestígio.",
           "Média", "Grande", "Pequena", "Broto", "Média", "Quero um suco natural", "Laranja",
           "Substitui a coca por guaraná"]


def test_order_2_replay_has_one_quatro_queijos_and_the_soda_swapped():
    chat = Chat(trigger={"action": "start_order"})
    replies = [chat.say(text) for text in ORDER_2]
    assert "4x" not in "".join(replies)
    assert "Troquei: 1x Refrigerante 2L (Coca-Cola) → 1x Refrigerante 2L (Guaraná Antarctica)" in replies[-1]
    assert chat.cart() == sorted([
        ("Mussarela", "Média", 1), ("Calabresa", "Grande", 1), ("Quatro Queijos Premium", "Broto", 1),
        ("Prestígio", "Média", 1), ("Suco Natural", "Laranja", 1), ("Refrigerante 2L", "Guaraná Antarctica", 1)])
    assert "Coca-Cola" not in replies[-1].split("→")[-1]
    # original address lacked number and city: only those are asked, then the fee stays pending
    chat.say("Entrega")
    assert chat.say("Sepetiba, Jardim espírito santo").endswith("Qual é o número? (se não tiver, responda *sem número*)")
    assert chat.say("266").endswith("Qual é a cidade?")
    assert chat.say("Uberlândia") == "Em qual nome fica o pedido?"
    summary = chat.say("Arthur")
    assert "Entrega em: Sepetiba, 266 - Jardim espírito santo, Uberlândia" in summary
    assert "Subtotal dos produtos: R$ 254,60" in summary and "Total final: pendente" in summary
    assert "Taxa de entrega: a confirmar pela loja" in summary and "\nTotal: " not in summary


# 3/4/5/6. cart operations ──────────────────────────────────────────────────────────────────────

def _cart_with(*texts):
    chat = Chat(trigger={"action": "start_order"})
    for text in texts:
        chat.say(text)
    return chat


def test_add_coca_asks_package_and_never_defaults():
    chat = _cart_with("quero")
    reply = chat.say("Quero uma Coca-Cola")
    assert "1) Refrigerante Lata" in reply and "2) Refrigerante 2L" in reply and chat.cart() == []
    chat.say("lata")
    assert chat.cart() == [("Refrigerante Lata", "Coca-Cola", 1)]
    chat2 = _cart_with("quero")
    chat2.say("quero um refrigerante 2l")
    assert chat2.cart() == [] and chat2.draft["pending"][0]["name"] == "Refrigerante 2L"  # option pending, not Coca


@pytest.mark.parametrize("text", ["Troca a Coca por Antarctica", "troca a coca pelo guaraná", "Substitui a coca por guaraná"])
def test_replace_option_keeps_other_items(text):
    chat = _cart_with("quero uma calabresa grande e uma coca 2 litros")
    reply = chat.say(text)
    assert "Troquei" in reply
    assert chat.cart() == sorted([("Calabresa", "Grande", 1), ("Refrigerante 2L", "Guaraná Antarctica", 1)])


def test_correction_changes_the_current_choice_without_adding():
    chat = _cart_with("quero uma calabresa grande e uma coca 2 litros")
    chat.say("Na verdade, quero Antarctica")
    assert chat.cart() == sorted([("Calabresa", "Grande", 1), ("Refrigerante 2L", "Guaraná Antarctica", 1)])


def test_add_also_keeps_coca_and_adds_guarana():
    chat = _cart_with("quero uma coca 2 litros")
    chat.say("Adiciona também um Guaraná")
    assert chat.cart() == sorted([("Refrigerante 2L", "Coca-Cola", 1), ("Refrigerante 2L", "Guaraná Antarctica", 1)])


def test_asked_for_both_keeps_both():
    chat = _cart_with("quero uma coca 2 litros e um guaraná 2 litros")
    assert chat.cart() == sorted([("Refrigerante 2L", "Coca-Cola", 1), ("Refrigerante 2L", "Guaraná Antarctica", 1)])


def test_remove_and_ambiguous_remove_asks_which():
    chat = _cart_with("quero uma calabresa grande e uma coca 2 litros")
    assert "Removi: 1x Refrigerante 2L (Coca-Cola)" in chat.say("Tira a Coca")
    assert chat.cart() == [("Calabresa", "Grande", 1)]
    chat = _cart_with("quero uma coca lata e uma coca 2 litros")
    reply = chat.say("tira a coca")
    assert "Qual item você quer tirar?" in reply and len(chat.cart()) == 2
    chat.say("2")
    assert chat.cart() == [("Refrigerante Lata", "Coca-Cola", 1)]


@pytest.mark.parametrize("text", ["Tira a Coca", "cancela a coca", "troca a coca por guaraná"])
def test_editing_an_item_that_is_not_in_the_cart_never_adds_it(text):
    chat = _cart_with("quero uma calabresa grande e um guaraná 2 litros")
    before = chat.cart()
    reply = chat.say(text)
    assert "Não encontrei" in reply and chat.cart() == before


def test_cancel_the_whole_order_still_works():
    chat = _cart_with("quero uma calabresa grande")
    assert "cancelei este pedido" in chat.say("cancela o pedido") and chat.result.draft is None


def test_change_quantity_of_item_in_context():
    chat = _cart_with("quero 4 pizzas de quatro queijos broto")
    assert chat.cart() == [("Quatro Queijos Premium", "Broto", 4)]
    assert "Alterei: 4x Quatro Queijos Premium (Broto) → 1x" in chat.say("Quero só uma")
    assert chat.cart() == [("Quatro Queijos Premium", "Broto", 1)]


@pytest.mark.parametrize("typed", ["Antartica", "Antarctica", "antártica"])
def test_misspelled_option_is_recognized(typed):
    chat = _cart_with("quero um refrigerante 2l")
    chat.say(typed)
    assert chat.cart() == [("Refrigerante 2L", "Guaraná Antarctica", 1)] and not chat.draft["pending"]


def test_pending_option_is_not_in_cart_until_chosen():
    chat = _cart_with("quero uma calabresa grande")
    chat.say("Quero um suco natural")
    assert chat.cart() == [("Calabresa", "Grande", 1)] and chat.draft["stage"] == "variant"
    chat.say("Laranja")
    assert ("Suco Natural", "Laranja", 1) in chat.cart()


def test_same_message_id_twice_applies_the_change_once():
    chat = _cart_with("quero uma calabresa grande")
    chat.say("adiciona também uma água mineral", message_id="wamid.x")
    chat.say("adiciona também uma água mineral", message_id="wamid.x")
    assert ("Água Mineral", None, 1) in chat.cart()


# 7/8. address ──────────────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("text,expected", [
    ("Rua Sepetiba, 266, Jardim Espírito Santo, Uberlândia",
     {"street": "Rua Sepetiba", "number": "266", "neighborhood": "Jardim Espírito Santo", "city": "Uberlândia"}),
    ("Sepetiba, Jardim espírito santo", {"street": "Sepetiba", "neighborhood": "Jardim espírito santo"}),
    ("Rua A sem número, Centro, Uberlândia, casa azul",
     {"street": "Rua A", "number": "s/n", "neighborhood": "Centro", "city": "Uberlândia", "complement": "casa azul"}),
])
def test_address_parsing_never_invents(text, expected):
    assert parse_address(text) == expected


def test_incomplete_address_asks_only_missing_fields_and_pickup_asks_none():
    chat = _cart_with("quero uma calabresa grande", "não", "entrega")
    assert chat.say("Rua das Flores, Centro").endswith("Qual é o número? (se não tiver, responda *sem número*)")
    assert chat.say("sem número").endswith("Qual é a cidade?")
    assert chat.say("Uberlândia") == "Em qual nome fica o pedido?"
    assert chat.draft["address"] == "Rua das Flores, s/n - Centro, Uberlândia"
    pickup = _cart_with("quero uma calabresa grande", "não")
    assert pickup.say("retirada") == "Em qual nome fica o pedido?"
    assert "Total: R$ 62,90" in pickup.say("Ana") and "pendente" not in pickup.result.reply


# 9/10. fees and confirmation after changes ─────────────────────────────────────────────────────

def _delivery_ready():
    chat = _cart_with("quero uma calabresa grande e uma coca 2 litros", "não", "entrega",
                      "Rua das Flores, 10, Centro, Uberlândia")
    chat.say("Arthur")
    return chat


def test_change_after_summary_requires_a_new_confirmation():
    chat = _delivery_ready()
    first = chat.draft["summary"]["signature"]
    reply = chat.say("troca a coca por antarctica")
    assert "Troquei" in reply and "Confira seu pedido" in reply and "Guaraná Antarctica" in reply
    assert chat.draft["summary"]["signature"] != first and not chat.assistant.orders.created
    chat.say("sim")
    order = chat.assistant.orders.created[0]
    assert [(p["product_name"], p["variant_name"]) for p in order["priced"]] == [
        ("Calabresa", "Grande"), ("Refrigerante 2L", "Guaraná Antarctica")]
    assert "aguardando a confirmação da loja" in chat.result.reply and "Total final: pendente" in chat.result.reply


def test_change_of_address_after_summary_needs_new_summary():
    chat = _delivery_ready()
    assert "novo endereço" in chat.say("quero mudar o endereço")
    assert chat.draft.get("summary") is None
    chat.say("Rua B, 20, Centro, Uberlândia")
    assert "Entrega em: Rua B, 20 - Centro, Uberlândia" in chat.result.reply


def test_customer_accepts_or_refuses_the_final_total():
    pending = {"id": 9, "order_number": 3, "status": "aguardando_cliente", "subtotal_cents": 7690,
               "delivery_fee_cents": 800, "total_cents": 8490, "fee_sent_at": datetime.utcnow() - timedelta(minutes=1)}
    chat = Chat()
    chat.assistant.orders.pending = dict(pending)
    reply = chat.say("aceito")
    assert "total final R$ 84,90" in reply and "confirmado" in reply and chat.assistant.orders.decisions == [True]
    chat = Chat()
    chat.assistant.orders.pending = dict(pending)
    assert "cancelado" in chat.say("cancelar") and chat.assistant.orders.decisions == [False]
    chat = Chat()
    chat.assistant.orders.pending = dict(pending)
    assert chat.say("oi, tudo bem?") is None and chat.assistant.orders.decisions == []


def test_status_labels_for_pending_fee():
    assert order_domain.STATUS_LABELS["aguardando_loja"] == "Aguardando confirmação da loja"
    text = order_domain.notification_text("aguardando_cliente", 3, "Bella", fee_cents=800, total_cents=8490)
    assert "R$ 8,00" in text and "R$ 84,90" in text and "ACEITO" in text
