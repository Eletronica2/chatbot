"""Dashboard metric models for superadmin and tenant views."""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class DashboardKpi(BaseModel):
    label: str
    value: str
    helper: str | None = None
    tone: str = "default"


class DashboardPlanBreakdown(BaseModel):
    plan: str
    tenants: int
    estimated_mrr_cents: int = 0


class DashboardTopTenant(BaseModel):
    tenant_id: str
    tenant_name: str
    plan: str
    status: str
    used_messages: int
    monthly_message_limit: int


class DashboardRecentEvent(BaseModel):
    action: str
    summary: str
    tenant_id: str
    actor_email: str | None = None
    created_at: datetime | None = None


class DashboardOverview(BaseModel):
    scope: str
    tenant_id: str | None = None
    tenant_name: str | None = None
    kpis: list[DashboardKpi] = Field(default_factory=list)
    plan_breakdown: list[DashboardPlanBreakdown] = Field(default_factory=list)
    top_tenants: list[DashboardTopTenant] = Field(default_factory=list)
    recent_events: list[DashboardRecentEvent] = Field(default_factory=list)

