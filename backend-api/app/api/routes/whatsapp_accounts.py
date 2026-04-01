"""Admin endpoints to manage tenant WhatsApp accounts."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request

from app.api.access import resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.domain.whatsapp_account import WhatsAppAccount, WhatsAppAccountCreate, WhatsAppAccountUpdate
from app.services.admin_audit_service import AdminAuditService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    whatsapp_account_service_dependency,
)
from app.services.whatsapp_account_service import WhatsAppAccountService

router = APIRouter(prefix="/api/v1/tenants/{tenant_id}/whatsapp-accounts", tags=["WhatsApp Accounts"])


@router.get("", response_model=list[WhatsAppAccount])
async def list_accounts(
    request: Request,
    tenant_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppAccountService = Depends(whatsapp_account_service_dependency),
) -> list[WhatsAppAccount]:
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    return await service.list_accounts(target_tenant_id)


@router.post("", response_model=WhatsAppAccount)
async def create_account(
    request: Request,
    tenant_id: str,
    payload: WhatsAppAccountCreate,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppAccountService = Depends(whatsapp_account_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> WhatsAppAccount:
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    item = await service.create_account(target_tenant_id, payload)
    await audit_service.append(
        tenant_id=target_tenant_id,
        action="whatsapp_account.create",
        entity_type="whatsapp_account",
        entity_key=item.account_key,
        summary=f"Conta WhatsApp {item.display_name} criada",
        actor=user,
        metadata={
            "phone_number_id": item.phone_number_id,
            "status": item.status,
            "is_default": item.is_default,
        },
    )
    return item


@router.patch("/{account_key}", response_model=WhatsAppAccount)
async def patch_account(
    request: Request,
    tenant_id: str,
    account_key: str,
    payload: WhatsAppAccountUpdate,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppAccountService = Depends(whatsapp_account_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> WhatsAppAccount:
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    try:
        item = await service.update_account(target_tenant_id, account_key, payload)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    await audit_service.append(
        tenant_id=target_tenant_id,
        action="whatsapp_account.update",
        entity_type="whatsapp_account",
        entity_key=item.account_key,
        summary=f"Conta WhatsApp {item.display_name} atualizada",
        actor=user,
        metadata={
            "phone_number_id": item.phone_number_id,
            "status": item.status,
            "is_default": item.is_default,
        },
    )
    return item

