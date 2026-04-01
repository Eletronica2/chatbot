"""Public billing webhooks."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException, Request

from app.services.billing_service import BillingService
from app.services.dependencies import billing_service_dependency

router = APIRouter(prefix="/api/v1/billing/webhooks", tags=["Billing Webhooks"])


@router.post("/stripe")
async def stripe_webhook(
    request: Request,
    stripe_signature: str | None = Header(default=None, alias="Stripe-Signature"),
    billing_service: BillingService = Depends(billing_service_dependency),
) -> dict:
    payload = await request.body()
    try:
        return await billing_service.handle_webhook(
            payload=payload,
            signature=stripe_signature,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

