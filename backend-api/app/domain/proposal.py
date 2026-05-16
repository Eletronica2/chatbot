"""Domain models for commercial proposals."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field


class Proposal(BaseModel):
    """Proposta comercial enviada/preparada para um lead.

    `included_items` e uma lista de strings (nome do item incluido no plano:
    "Automacao base", "Treinamento", etc.).
    """

    id: str
    lead_id: str | None = None
    tenant_id: str | None = None
    company_name: str
    contact_name: str
    contact_email: str
    contact_whatsapp: str | None = None
    plan: str
    monthly_value: Decimal = Field(default=Decimal("0"))
    setup_fee: Decimal = Field(default=Decimal("0"))
    monthly_message_limit: int = 1000
    included_items: list[str] = Field(default_factory=list)
    validity_days: int = 7
    status: str = "draft"
    notes: str | None = None
    created_by_user_id: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


class PlanRecommendation(BaseModel):
    """Recomendacao automatica de plano baseada em volume mensal estimado."""

    plan: str
    plan_label: str
    monthly_value: Decimal
    setup_fee: Decimal
    monthly_message_limit: int
    included_items: list[str]
    rationale: str
