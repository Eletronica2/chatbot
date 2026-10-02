"""Domain models for commercial proposals."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any

from pydantic import BaseModel, Field


class Proposal(BaseModel):
    """Proposta comercial enviada/preparada para um lead.

    Propostas sem `catalog_version` são históricas (catálogo V1) e mantêm o
    preço, limite e texto originais.
    """

    id: str
    lead_id: str | None = None
    tenant_id: str | None = None
    company_name: str
    contact_name: str
    contact_email: str
    contact_whatsapp: str | None = None
    plan: str
    catalog_version: str | None = None
    plan_code: str | None = None
    billing_mode: str | None = None
    monthly_value: Decimal = Field(default=Decimal("0"))
    setup_fee: Decimal = Field(default=Decimal("0"))
    monthly_message_limit: int = 1000
    operational_volume: int | None = None
    marketing_volume: int | None = None
    marketing_estimate: Decimal | None = None
    included_items: list[str] = Field(default_factory=list)
    pricing_snapshot: dict[str, Any] | None = None
    margin_snapshot: dict[str, Any] | None = None
    margin_override_reason: str | None = None
    validity_days: int = 7
    status: str = "draft"
    notes: str | None = None
    created_by_user_id: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    @property
    def is_legacy(self) -> bool:
        return not self.catalog_version


class PlanRecommendation(BaseModel):
    """Recomendação de plano V2: base = volume operacional; marketing é adicional."""

    plan: str
    plan_code: str
    plan_label: str
    catalog_version: str
    billing_mode: str
    monthly_value: Decimal | None
    is_custom: bool = False
    setup_fee: Decimal
    monthly_message_limit: int | None
    operational_volume: int | None = None
    operational_answer: str | None = None
    marketing_volume: int | None = None
    marketing_answer: str | None = None
    marketing_unit_price: Decimal | None = None
    marketing_estimate: Decimal | None = None
    included_items: list[str]
    rationale: str
    warning: str | None = None
    topup_offers: list[dict[str, Any]] = Field(default_factory=list)
    margin: dict[str, Any] | None = None
