"""Domain models for billing flows and Stripe-backed subscriptions."""
from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


BillingProvider = Literal["stripe", "manual"]
BillingCustomerStatus = Literal["active", "trialing", "past_due", "canceled", "inactive"]
BillingInvoiceStatus = Literal["draft", "open", "paid", "uncollectible", "void", "past_due"]


class BillingCheckoutSession(BaseModel):
    provider: BillingProvider = "stripe"
    checkout_url: str
    session_id: str
    plan: str


class BillingPortalSession(BaseModel):
    provider: BillingProvider = "stripe"
    portal_url: str


class BillingCustomerSnapshot(BaseModel):
    tenant_id: str
    provider: BillingProvider = "stripe"
    provider_customer_id: str
    provider_subscription_id: str | None = None
    provider_price_id: str | None = None
    status: BillingCustomerStatus = "inactive"
    current_period_end: datetime | None = None
    checkout_url: str | None = None
    portal_url: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


class BillingInvoiceSnapshot(BaseModel):
    tenant_id: str
    provider_invoice_id: str
    provider_subscription_id: str | None = None
    status: BillingInvoiceStatus = "draft"
    hosted_invoice_url: str | None = None
    invoice_pdf_url: str | None = None
    amount_due: int = 0
    amount_paid: int = 0
    currency: str = "brl"
    due_date: datetime | None = None
    paid_at: datetime | None = None
    created_at: datetime | None = None


class BillingSummary(BaseModel):
    tenant_id: str
    provider: BillingProvider = "stripe"
    provider_ready: bool = False
    subscription_status: str
    current_plan: str
    renewal_date: datetime | None = None
    monthly_message_limit: int = 0
    used_messages: int = 0
    remaining_messages: int = 0
    grace_days: int = 0
    customer: BillingCustomerSnapshot | None = None
    invoices: list[BillingInvoiceSnapshot] = Field(default_factory=list)
    available_plans: list[str] = Field(default_factory=list)

