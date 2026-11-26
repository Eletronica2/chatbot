from decimal import Decimal
from types import SimpleNamespace

from app.services.campaign_meta_estimate import (
    META_BILLING_DISCLAIMER,
    estimate_actual_spend,
    estimate_campaign_cost,
)


class _Engine:
    def resolve(self, category, **kwargs):
        return SimpleNamespace(
            id=1,
            currency="BRL",
            billing_basis="per_delivered_message",
            free_allowance=0,
            category=category,
            unit_price=Decimal("0.42"),
        )


def test_billable_units_no_double_count_delivered_and_read():
    est = estimate_actual_spend(
        rate_engine=_Engine(),
        category="MARKETING",
        delivered_count=3,
        read_count=7,
    )
    assert est["billable_units_estimate"] == 10


def test_estimate_includes_disclaimer():
    est = estimate_campaign_cost(rate_engine=_Engine(), category="MARKETING", recipient_count=10)
    assert est["disclaimer"] == META_BILLING_DISCLAIMER
    assert est["is_official_invoice"] is False
    assert Decimal(est["total_if_all_delivered_estimate"]) >= 0