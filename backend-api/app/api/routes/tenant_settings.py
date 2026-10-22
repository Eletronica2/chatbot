"""Tenant settings API used by admin-panel."""
from __future__ import annotations

from typing import List, Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.access import assert_superadmin, resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.domain.tenant import TenantSettings
from app.services.dependencies import admin_audit_service_dependency, authenticated_user_dependency, tenant_settings_service_dependency
from app.services.admin_audit_service import AdminAuditService
from app.services.tenant_settings_service import TenantSettingsService

router = APIRouter(prefix="/api/v1/tenants", tags=["Tenant Settings"])


class TenantSettingsPatchPayload(BaseModel):
    tenant_name: Optional[str] = None
    ai_enabled: Optional[bool] = None
    flow_editing_enabled: Optional[bool] = None
    debug_mode: Optional[bool] = None
    ai_provider: Optional[Literal["gemini", "local"]] = None
    local_ai_enabled: Optional[bool] = None
    gemini_model: Optional[str] = None
    fallback_models: Optional[List[str]] = None
    auto_reply_mode: Optional[Literal["on", "off", "allowlist"]] = None
    auto_reply_allowlist: Optional[List[str]] = Field(default=None, max_length=20)


class TenantSettingsResponse(BaseModel):
    tenant_id: str
    tenant_name: str
    ai_enabled: bool
    flow_editing_enabled: bool
    debug_mode: bool
    gemini_model: str
    fallback_models: List[str] = Field(default_factory=list)
    available_models: List[str] = Field(default_factory=list)
    ai_provider: str = "gemini"
    local_ai_enabled: bool = False
    auto_reply_mode: str = "on"
    auto_reply_allowlist_count: int = 0

    @classmethod
    def from_domain(cls, item: TenantSettings) -> "TenantSettingsResponse":
        data = item.model_dump(exclude={"auto_reply_allowlist"})
        return cls(**data, auto_reply_allowlist_count=len(item.auto_reply_allowlist))


def assert_tenant_settings_patch_access(
    user: AuthenticatedUser,
    payload: TenantSettingsPatchPayload,
) -> None:
    if (payload.gemini_model is not None or payload.fallback_models is not None
            or payload.ai_provider is not None or payload.local_ai_enabled is not None
            or payload.auto_reply_mode is not None or payload.auto_reply_allowlist is not None):
        assert_superadmin(user)


@router.get("/{tenant_id}/settings", response_model=TenantSettingsResponse)
async def get_tenant_settings(
    request: Request,
    tenant_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: TenantSettingsService = Depends(tenant_settings_service_dependency),
) -> TenantSettingsResponse:
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    settings = await service.get_or_create(target_tenant_id)
    return TenantSettingsResponse.from_domain(settings)


@router.patch("/{tenant_id}/settings", response_model=TenantSettingsResponse)
async def patch_tenant_settings(
    request: Request,
    tenant_id: str,
    payload: TenantSettingsPatchPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: TenantSettingsService = Depends(tenant_settings_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> TenantSettingsResponse:
    assert_tenant_settings_patch_access(user, payload)
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    try:
        updated = await service.update(
            target_tenant_id,
            tenant_name=payload.tenant_name,
            ai_enabled=payload.ai_enabled,
            flow_editing_enabled=payload.flow_editing_enabled,
            debug_mode=payload.debug_mode,
            ai_provider=payload.ai_provider,
            local_ai_enabled=payload.local_ai_enabled,
            gemini_model=payload.gemini_model,
            fallback_models=payload.fallback_models,
            auto_reply_mode=payload.auto_reply_mode,
            auto_reply_allowlist=payload.auto_reply_allowlist,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if payload.auto_reply_mode is not None or payload.auto_reply_allowlist is not None:
        await audit_service.append(
            tenant_id=target_tenant_id, action="tenant.auto_reply.update", entity_type="tenant_settings",
            entity_key=target_tenant_id, summary="Resposta automática do tenant atualizada", actor=user,
            metadata={"auto_reply_mode": updated.auto_reply_mode,
                      "auto_reply_allowlist_count": len(updated.auto_reply_allowlist)},
        )
    if payload.ai_provider is not None or payload.local_ai_enabled is not None:
        await audit_service.append(
            tenant_id=target_tenant_id, action="tenant.ai_provider.update", entity_type="tenant_settings",
            entity_key=target_tenant_id, summary="Provider de IA do tenant atualizado", actor=user,
            metadata={"ai_provider": updated.ai_provider, "local_ai_enabled": updated.local_ai_enabled},
        )
    return TenantSettingsResponse.from_domain(updated)

