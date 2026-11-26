"""Meta message cost estimates (never official invoices)."""
from __future__ import annotations

from decimal import Decimal
from typing import Any

from app.services.meta_rate_engine import MetaRateEngine, effective_unit_cost

META_BILLING_DISCLAIMER = (
    "As mensagens são cobradas diretamente pela Meta na forma de pagamento vinculada "
    "à sua conta WhatsApp Business. Os valores apresentados pelo Atende Ai são estimativas."
)


def estimate_campaign_cost(
    *,
    rate_engine: MetaRateEngine,
    category: str,
    recipient_count: int,
    market: str = "BR",
    currency: str = "BRL",
    pricing_analytics_hint: dict[str, Any] | None = None,
) -> dict[str, Any]:
    count = max(0, int(recipient_count))
    card = rate_engine.resolve(category, market=market, currency=currency)
    unit = effective_unit_cost(card, prior_usage_in_scope=0) if card else None
    unit_dec = unit if unit is not None else Decimal("0")
    total = unit_dec * Decimal(count)
    payload: dict[str, Any] = {
        "market": market,
        "currency": card.currency if card else currency,
        "category": str(category or "UTILITY").upper(),
        "recipients": count,
        "unit_price_estimate": str(unit_dec),
        "total_if_all_delivered_estimate": str(total),
        "billing_basis": card.billing_basis if card else "per_delivered_message",
        "free_allowance": card.free_allowance if card else 0,
        "rate_card_id": card.id if card else None,
        "source": "meta_rate_cards",
        "disclaimer": META_BILLING_DISCLAIMER,
        "is_official_invoice": False,
    }
    if pricing_analytics_hint:
        payload["pricing_analytics_ref"] = pricing_analytics_hint
    return payload


def estimate_actual_spend(
    *,
    rate_engine: MetaRateEngine,
    category: str,
    delivered_count: int,
    read_count: int,
    market: str = "BR",
) -> dict[str, Any]:
    """Recipients are in a single terminal bucket (read replaces delivered in our model)."""
    card = rate_engine.resolve(category, market=market)
    unit = effective_unit_cost(card, 0) if card else Decimal("0")
    billable_units = max(0, int(delivered_count)) + max(0, int(read_count))
    return {
        "currency": card.currency if card else "BRL",
        "billable_units_estimate": billable_units,
        "consumption_estimate": str(unit * Decimal(billable_units)),
        "disclaimer": META_BILLING_DISCLAIMER,
        "is_official_invoice": False,
        "source": "meta_rate_cards",
    }