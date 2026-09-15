"""Usage ledger and Meta rate card endpoints."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from pydantic import BaseModel, Field

from app.api.access import assert_capability, resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.services.dependencies import (
    authenticated_user_dependency,
    billing_service_dependency,
    internal_api_dependency,
    usage_ledger_service_dependency,
)
from app.services.billing_service import BillingService
from app.services.usage_ledger_service import UsageLedgerService

router = APIRouter(tags=["Usage"])


class DeliveredUsagePayload(BaseModel):
    tenant_id: str = Field(..., min_length=1)
    provider_message_id: str = Field(..., min_length=1)
    category: str | None = None
    market: str = "BR"
    quantity: int = 1


@router.get("/api/v1/usage")
async def list_usage_period(
    request: Request,
    period: str = Query(..., description="Billing period YYYY-MM"),
    format: str | None = Query(default=None, description="Set to csv for download"),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: UsageLedgerService = Depends(usage_ledger_service_dependency),
) -> Any:
    assert_capability(user, "canManageBilling")
    tenant_id = resolve_tenant_scope(user, request)
    try:
        events = await service.list_period(tenant_id, period)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if (format or "").strip().lower() == "csv":
        csv_body = service.export_csv(events)
        return Response(
            content=csv_body,
            media_type="text/csv",
            headers={"Content-Disposition": f'attachment; filename="usage-{period}.csv"'},
        )
    return {"tenant_id": tenant_id, "period": period, "events": events}


@router.get("/api/v1/usage/meta-rates")
async def get_meta_rates(
    request: Request,
    market: str = Query(default="BR"),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: UsageLedgerService = Depends(usage_ledger_service_dependency),
) -> dict[str, Any]:
    resolve_tenant_scope(user, request)
    cards = await service.get_meta_rate_cards(market=market)
    return {"market": market.upper(), "rates": cards}


@router.post(
    "/api/v1/internal/usage/delivered",
    dependencies=[Depends(internal_api_dependency)],
)
async def internal_record_delivered(
    payload: DeliveredUsagePayload,
    usage_service: UsageLedgerService = Depends(usage_ledger_service_dependency),
    billing_service: BillingService = Depends(billing_service_dependency),
) -> dict[str, Any]:
    result = await usage_service.record_delivered(
        payload.tenant_id,
        payload.provider_message_id,
        category=payload.category,
        market=payload.market,
        quantity=payload.quantity,
    )
    if result.get("created"):
        # Meter reporting must never block WhatsApp delivery path.
        await billing_service.report_meter_event(
            payload.tenant_id,
            payload.provider_message_id,
            quantity=payload.quantity,
        )
    return result
