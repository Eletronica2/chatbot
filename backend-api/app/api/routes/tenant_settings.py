"""Tenant settings API used by admin-panel."""
from __future__ import annotations

from typing import List, Optional

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field

from app.api.access import resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.domain.tenant import TenantSettings
from app.services.dependencies import authenticated_user_dependency, tenant_settings_service_dependency
from app.services.tenant_settings_service import TenantSettingsService

router = APIRouter(prefix="/api/v1/tenants", tags=["Tenant Settings"])


class TenantSettingsPatchPayload(BaseModel):
    tenant_name: Optional[str] = None
    ai_enabled: Optional[bool] = None
    flow_editing_enabled: Optional[bool] = None
    debug_mode: Optional[bool] = None
    gemini_model: Optional[str] = None
    fallback_models: Optional[List[str]] = None


class TenantSettingsResponse(BaseModel):
    tenant_id: str
    tenant_name: str
    ai_enabled: bool
    flow_editing_enabled: bool
    debug_mode: bool
    gemini_model: str
    fallback_models: List[str] = Field(default_factory=list)
    available_models: List[str] = Field(default_factory=list)

    @classmethod
    def from_domain(cls, item: TenantSettings) -> "TenantSettingsResponse":
        return cls(**item.model_dump())


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
) -> TenantSettingsResponse:
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    updated = await service.update(
        target_tenant_id,
        tenant_name=payload.tenant_name,
        ai_enabled=payload.ai_enabled,
        flow_editing_enabled=payload.flow_editing_enabled,
        debug_mode=payload.debug_mode,
        gemini_model=payload.gemini_model,
        fallback_models=payload.fallback_models,
    )
    return TenantSettingsResponse.from_domain(updated)

