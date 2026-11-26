"""Internal endpoints used by the WhatsApp gateway."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.services.dependencies import (
    internal_api_dependency,
    whatsapp_account_service_dependency,
    whatsapp_template_status_service_dependency,
)
from app.services.whatsapp_account_service import WhatsAppAccountService
from app.services.whatsapp_template_status_service import WhatsAppTemplateStatusService

router = APIRouter(prefix="/api/v1/internal/whatsapp", tags=["Internal WhatsApp"])


class ResolveAccountPayload(BaseModel):
    tenant_id: str | None = None
    phone_number_id: str | None = None


class VerifyTokenPayload(BaseModel):
    verify_token: str


class TemplateStatusWebhookPayload(BaseModel):
    waba_id: str
    entry_time: int = 0
    value: dict


@router.post("/resolve", dependencies=[Depends(internal_api_dependency)])
async def resolve_account(
    payload: ResolveAccountPayload,
    service: WhatsAppAccountService = Depends(whatsapp_account_service_dependency),
) -> dict:
    account = None
    if payload.phone_number_id:
        account = await service.resolve_for_phone_number_id(payload.phone_number_id)
    if account is None and payload.tenant_id:
        account = await service.resolve_for_tenant(payload.tenant_id)
    if account is None:
        return {"found": False}
    return {
        "found": True,
        "tenant_id": account.account.tenant_id,
        "account_key": account.account.account_key,
        "display_name": account.account.display_name,
        "phone_number_id": account.account.phone_number_id,
        "display_phone_number": account.account.display_phone_number,
        "verify_token": account.account.verify_token,
        "access_token": account.access_token,
    }


@router.post("/verify-token", dependencies=[Depends(internal_api_dependency)])
async def verify_token(
    payload: VerifyTokenPayload,
    service: WhatsAppAccountService = Depends(whatsapp_account_service_dependency),
) -> dict:
    return {"valid": await service.validate_verify_token(payload.verify_token)}


@router.post("/template-status", dependencies=[Depends(internal_api_dependency)])
async def template_status_webhook(
    payload: TemplateStatusWebhookPayload,
    service: WhatsAppTemplateStatusService = Depends(whatsapp_template_status_service_dependency),
) -> dict:
    try:
        return await service.ingest_webhook(
            waba_id=payload.waba_id,
            entry_time=payload.entry_time,
            value=payload.value if isinstance(payload.value, dict) else {},
        )
    except ValueError as exc:
        return {"applied": False, "reason": str(exc)}

