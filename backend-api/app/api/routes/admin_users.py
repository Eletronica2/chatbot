"""Backoffice endpoints for tenant user management."""
from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.access import resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.domain.user_admin import TenantUser, TenantUserActionToken
from app.services.admin_audit_service import AdminAuditService
from app.services.email_service import EmailService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    email_service_dependency,
    tenant_user_service_dependency,
)
from app.services.tenant_user_service import TenantUserService

router = APIRouter(prefix="/api/v1/tenants/{tenant_id}/users", tags=["Tenant Users"])

_ALLOWED_USER_MANAGER_ROLES = {"owner", "manager", "superadmin", "system-admin", "system_admin", "systemadmin"}


def _assert_user_management_access(user: AuthenticatedUser) -> None:
    if user.role.strip().lower() not in _ALLOWED_USER_MANAGER_ROLES:
        raise HTTPException(status_code=403, detail="Permissao insuficiente para gerir usuarios")


class TenantUserResponse(BaseModel):
    user_id: str
    tenant_id: str
    email: str
    display_name: str
    role: str
    status: str
    created_at: datetime | None = None
    last_login_at: datetime | None = None

    @classmethod
    def from_domain(cls, item: TenantUser) -> "TenantUserResponse":
        return cls(**item.model_dump())


class TenantUserInvitePayload(BaseModel):
    email: str = Field(..., min_length=5)
    display_name: str = Field(..., min_length=2)
    role: str = Field(default="manager")


class TenantUserPatchPayload(BaseModel):
    display_name: str | None = Field(default=None, min_length=2)
    role: str | None = None
    status: str | None = None


class TenantUserActionTokenResponse(BaseModel):
    token_type: str
    token: str
    expires_at: datetime
    action_url: str
    user: TenantUserResponse
    email_status: str | None = None
    email_error: str | None = None

    @classmethod
    def from_domain(cls, item: TenantUserActionToken) -> "TenantUserActionTokenResponse":
        return cls(
            token_type=item.token_type,
            token=item.token,
            expires_at=item.expires_at,
            action_url=item.action_url,
            user=TenantUserResponse.from_domain(item.user),
            email_status=item.email_status,
            email_error=item.email_error,
        )


@router.get("", response_model=list[TenantUserResponse])
async def list_tenant_users(
    request: Request,
    tenant_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: TenantUserService = Depends(tenant_user_service_dependency),
) -> list[TenantUserResponse]:
    _assert_user_management_access(user)
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    items = await service.list_users(target_tenant_id)
    return [TenantUserResponse.from_domain(item) for item in items]


@router.post("/invite", response_model=TenantUserActionTokenResponse)
async def invite_tenant_user(
    request: Request,
    tenant_id: str,
    payload: TenantUserInvitePayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: TenantUserService = Depends(tenant_user_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
    email_service: EmailService = Depends(email_service_dependency),
) -> TenantUserActionTokenResponse:
    _assert_user_management_access(user)
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    try:
        item = await service.invite_user(
            tenant_id=target_tenant_id,
            email=payload.email,
            display_name=payload.display_name,
            role=payload.role,
            created_by_user_id=user.user_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    tenant_record = service.database.get_tenant_record(target_tenant_id) or {}
    email_result = await email_service.send_invite_email(
        tenant_id=target_tenant_id,
        tenant_name=str(tenant_record.get("name") or target_tenant_id),
        to_email=item.user.email,
        display_name=item.user.display_name,
        action_url=item.action_url,
        expires_at=item.expires_at,
    )
    item = item.model_copy(
        update={
            "email_status": email_result.status,
            "email_error": email_result.error,
        }
    )
    await audit_service.append(
        tenant_id=target_tenant_id,
        action="user.invite",
        entity_type="user",
        entity_key=item.user.email,
        summary=f"Convite gerado para {item.user.display_name}",
        actor=user,
        metadata={
            "role": item.user.role,
            "token_type": item.token_type,
            "email_status": item.email_status,
        },
    )
    return TenantUserActionTokenResponse.from_domain(item)


@router.patch("/{user_id}", response_model=TenantUserResponse)
async def patch_tenant_user(
    request: Request,
    tenant_id: str,
    user_id: str,
    payload: TenantUserPatchPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: TenantUserService = Depends(tenant_user_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> TenantUserResponse:
    _assert_user_management_access(user)
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    try:
        item = await service.update_user(
            tenant_id=target_tenant_id,
            user_id=user_id,
            display_name=payload.display_name,
            role=payload.role,
            status=payload.status,
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    await audit_service.append(
        tenant_id=target_tenant_id,
        action="user.update",
        entity_type="user",
        entity_key=item.email,
        summary=f"Acesso atualizado para {item.display_name}",
        actor=user,
        metadata={
            "role": item.role,
            "status": item.status,
        },
    )
    return TenantUserResponse.from_domain(item)


@router.post("/{user_id}/reset-password", response_model=TenantUserActionTokenResponse)
async def reset_tenant_user_password(
    request: Request,
    tenant_id: str,
    user_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: TenantUserService = Depends(tenant_user_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
    email_service: EmailService = Depends(email_service_dependency),
) -> TenantUserActionTokenResponse:
    _assert_user_management_access(user)
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    try:
        item = await service.create_password_reset(
            tenant_id=target_tenant_id,
            user_id=user_id,
            created_by_user_id=user.user_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    tenant_record = service.database.get_tenant_record(target_tenant_id) or {}
    email_result = await email_service.send_reset_email(
        tenant_id=target_tenant_id,
        tenant_name=str(tenant_record.get("name") or target_tenant_id),
        to_email=item.user.email,
        display_name=item.user.display_name,
        action_url=item.action_url,
        expires_at=item.expires_at,
    )
    item = item.model_copy(
        update={
            "email_status": email_result.status,
            "email_error": email_result.error,
        }
    )
    await audit_service.append(
        tenant_id=target_tenant_id,
        action="user.reset_password",
        entity_type="user",
        entity_key=item.user.email,
        summary=f"Reset de senha gerado para {item.user.display_name}",
        actor=user,
        metadata={
            "token_type": item.token_type,
            "email_status": item.email_status,
        },
    )
    return TenantUserActionTokenResponse.from_domain(item)
