"""Embedded Signup onboarding endpoints."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.access import resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.domain.whatsapp_account import WhatsAppAccount
from app.services.admin_audit_service import AdminAuditService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    whatsapp_onboarding_service_dependency,
)
from app.services.whatsapp_onboarding_service import WhatsAppOnboardingService

router = APIRouter(tags=["WhatsApp Onboarding"])


class EmbeddedSignupExchangePayload(BaseModel):
    code: str = Field(..., min_length=1)
    waba_id: str = Field(..., min_length=1)
    phone_number_id: str = Field(..., min_length=1)
    display_phone_number: str = Field(..., min_length=1)
    display_name: str = Field(..., min_length=1)
    verify_token: str | None = None
    coexistence: bool = True
    redirect_uri: str | None = None


class EmbeddedSignupExchangeResponse(BaseModel):
    account: WhatsAppAccount
    coexistence: bool
    skip_register: bool
    phone_status: dict


@router.get("/api/v1/meta/embedded-signup/config")
async def embedded_signup_config(
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppOnboardingService = Depends(whatsapp_onboarding_service_dependency),
) -> dict:
    _ = user
    config = service.embedded_signup_config()
    if not config.get("app_id") or not config.get("config_id"):
        raise HTTPException(
            status_code=503,
            detail="Configure META_APP_ID e META_EMBEDDED_CONFIG_ID no backend",
        )
    return config


@router.post(
    "/api/v1/tenants/{tenant_id}/whatsapp-onboarding/exchange",
    response_model=EmbeddedSignupExchangeResponse,
)
async def exchange_embedded_signup(
    request: Request,
    tenant_id: str,
    payload: EmbeddedSignupExchangePayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppOnboardingService = Depends(whatsapp_onboarding_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> EmbeddedSignupExchangeResponse:
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    try:
        result = await service.complete_embedded_signup(
            tenant_id=target_tenant_id,
            code=payload.code,
            waba_id=payload.waba_id,
            phone_number_id=payload.phone_number_id,
            display_phone_number=payload.display_phone_number,
            display_name=payload.display_name,
            verify_token=payload.verify_token,
            coexistence=payload.coexistence,
            redirect_uri=payload.redirect_uri,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    account: WhatsAppAccount = result["account"]
    await audit_service.append(
        tenant_id=target_tenant_id,
        action="whatsapp_onboarding.embedded_signup",
        entity_type="whatsapp_account",
        entity_key=account.account_key,
        summary=f"Conta WhatsApp {account.display_name} conectada via Embedded Signup",
        actor=user,
        metadata={
            "phone_number_id": account.phone_number_id,
            "coexistence": payload.coexistence,
        },
    )
    return EmbeddedSignupExchangeResponse(
        account=account,
        coexistence=bool(result.get("coexistence")),
        skip_register=bool(result.get("skip_register")),
        phone_status=result.get("phone_status") or {},
    )
