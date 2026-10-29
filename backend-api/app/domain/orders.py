"""Orders module domain: status machine (pt-BR labels), money formatting, notification texts."""
from __future__ import annotations

FULFILLMENTS = ("entrega", "retirada")

# Stored value -> label shown to the store and the customer.
STATUS_LABELS = {
    "aguardando_loja": "Aguardando confirmação da loja",
    "aguardando_cliente": "Aguardando aceite do cliente",
    "novo": "Novo",
    "confirmado": "Confirmado",
    "em_preparo": "Em preparo",
    "saiu_para_entrega": "Saiu para entrega",
    "pronto_para_retirada": "Pronto para retirada",
    "entregue": "Entregue",
    "retirado": "Retirado",
    "cancelado": "Cancelado",
}

TERMINAL = {"entregue", "retirado", "cancelado"}

# Delivery orders wait for the store's fee (aguardando_loja) and the customer's acceptance of the final total
# (aguardando_cliente). Those steps only move through set_delivery_fee / customer_decision, never by hand.
_NEXT = {
    "aguardando_loja": {"cancelado"},
    "aguardando_cliente": {"cancelado"},
    "novo": {"confirmado", "cancelado"},
    "confirmado": {"em_preparo", "cancelado"},
    "em_preparo": {"saiu_para_entrega", "pronto_para_retirada", "cancelado"},
    "saiu_para_entrega": {"entregue", "cancelado"},
    "pronto_para_retirada": {"retirado", "cancelado"},
}
# Delivery and pickup have their own last steps.
_ONLY_FOR = {"saiu_para_entrega": "entrega", "entregue": "entrega", "pronto_para_retirada": "retirada",
             "retirado": "retirada"}


def allowed_next(status: str, fulfillment: str) -> list[str]:
    options = _NEXT.get(status, set())
    return [s for s in STATUS_LABELS if s in options and _ONLY_FOR.get(s, fulfillment) == fulfillment]


def can_transition(current: str, target: str, fulfillment: str) -> bool:
    return target in allowed_next(current, fulfillment)


def money(cents: int) -> str:
    reais, centavos = divmod(int(cents), 100)
    return f"R$ {reais:,}".replace(",", ".") + f",{centavos:02d}"


NOTIFICATION_TEXTS = {
    "aguardando_cliente": (
        "A taxa de entrega do pedido #{number} é {fee}. Total final: {total}. "
        "Responda *ACEITO* para confirmar ou *CANCELAR* para cancelar."
    ),
    "confirmado": "Seu pedido #{number} foi confirmado! Já vamos começar a preparar.",
    "em_preparo": "Seu pedido #{number} está em preparo.",
    "saiu_para_entrega": "Seu pedido #{number} saiu para entrega.",
    "pronto_para_retirada": "Seu pedido #{number} está pronto para retirada.",
    "entregue": "Seu pedido #{number} foi entregue. Bom apetite!",
    "retirado": "Seu pedido #{number} foi retirado. Bom apetite!",
    "cancelado": "Seu pedido #{number} foi cancelado. Se tiver alguma dúvida, é só responder por aqui.",
}


def notification_text(status: str, order_number: int, store_name: str, *, fee_cents: int | None = None,
                      total_cents: int | None = None) -> str:
    return f"{store_name}: " + NOTIFICATION_TEXTS[status].format(
        number=order_number, fee=money(fee_cents or 0), total=money(total_cents or 0)
    )
