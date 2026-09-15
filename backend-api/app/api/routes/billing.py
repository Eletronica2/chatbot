"""Billing endpoints for checkout, portal and subscription summaries."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from app.api.access import assert_capability, resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.domain.billing import BillingSummary
from app.services.billing_service import BillingService
from app.services.dependencies import (
    authenticated_user_dependency,
    billing_service_dependency,
    subscription_service_dependency,
    usage_ledger_service_dependency,
)
from app.services.subscription_service import SubscriptionService
from app.services.usage_ledger_service import UsageLedgerService

router = APIRouter(prefix="/api/v1/billing", tags=["Billing"])


class BillingCheckoutPayload(BaseModel):
    plan: str = Field(..., min_length=3)


class BillingCheckoutResponse(BaseModel):
    checkout_url: str
    session_id: str
    plan: str
    provider: str


class BillingPortalPayload(BaseModel):
    return_url: str | None = None


class BillingPortalResponse(BaseModel):
    portal_url: str
    provider: str


@router.get("/summary", response_model=BillingSummary)
async def get_billing_summary(
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    billing_service: BillingService = Depends(billing_service_dependency),
    subscription_service: SubscriptionService = Depends(subscription_service_dependency),
) -> BillingSummary:
    assert_capability(user, "canManageBilling")
    target_tenant_id = resolve_tenant_scope(user, request)
    subscription = await subscription_service.get_or_create(target_tenant_id)
    usage = await subscription_service.get_usage_snapshot(target_tenant_id)
    return await billing_service.get_summary(
        tenant_id=target_tenant_id,
        subscription=subscription,
        usage=usage,
    )


@router.post("/checkout-session", response_model=BillingCheckoutResponse)
async def create_checkout_session(
    request: Request,
    payload: BillingCheckoutPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    billing_service: BillingService = Depends(billing_service_dependency),
) -> BillingCheckoutResponse:
    assert_capability(user, "canManageBilling")
    target_tenant_id = resolve_tenant_scope(user, request)
    tenant_record = billing_service.database.get_tenant_record(target_tenant_id)
    if tenant_record is None:
        raise HTTPException(status_code=404, detail="Tenant nao encontrado")
    try:
        checkout = await billing_service.create_checkout_session(
            tenant_id=target_tenant_id,
            tenant_name=str(tenant_record.get("name") or target_tenant_id),
            customer_email=str(tenant_record.get("email") or user.email),
            customer_name=str(tenant_record.get("name") or user.display_name),
            plan=payload.plan.strip().lower(),
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return BillingCheckoutResponse(
        checkout_url=checkout.checkout_url,
        session_id=checkout.session_id,
        plan=checkout.plan,
        provider=checkout.provider,
    )


@router.post("/portal-session", response_model=BillingPortalResponse)
async def create_portal_session(
    request: Request,
    payload: BillingPortalPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    billing_service: BillingService = Depends(billing_service_dependency),
) -> BillingPortalResponse:
    assert_capability(user, "canManageBilling")
    target_tenant_id = resolve_tenant_scope(user, request)
    try:
        portal = await billing_service.create_portal_session(
            tenant_id=target_tenant_id,
            return_url=payload.return_url,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return BillingPortalResponse(portal_url=portal.portal_url, provider=portal.provider)


@router.get("/meta-rates")
async def billing_meta_rates(
    request: Request,
    market: str = Query(default="BR"),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: UsageLedgerService = Depends(usage_ledger_service_dependency),
) -> dict[str, Any]:
    """Alias for Flutter billing screens — same data as /api/v1/usage/meta-rates."""
    resolve_tenant_scope(user, request)
    cards = await service.get_meta_rate_cards(market=market)
    return {"market": market.upper(), "rates": cards, "consulted_docs": "2026-09-03"}


@router.get("/plans")
async def list_plans(
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    billing_service: BillingService = Depends(billing_service_dependency),
) -> dict[str, Any]:
    assert_capability(user, "canManageBilling")
    return {
        "plans": billing_service.available_plans(),
        "provider_ready": billing_service.provider_ready,
        "note": (
            "Atenda Ai cobra via Stripe (assinatura ou on-demand). "
            "Tarifas WhatsApp/Meta são cobradas diretamente pela Meta."
        ),
    }
