"""Tenant settings API used by admin-panel."""
from __future__ import annotations

from typing import List, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.domain.tenant import TenantSettings
from app.services.dependencies import tenant_settings_service_dependency
from app.services.tenant_settings_service import TenantSettingsService

router = APIRouter(prefix="/api/v1/tenants", tags=["Tenant Settings"])


class TenantSettingsPatchPayload(BaseModel):
    tenant_name: Optional[str] = None
    ai_enabled: Optional[bool] = None
    flow_editing_enabled: Optional[bool] = None
    gemini_model: Optional[str] = None
    fallback_models: Optional[List[str]] = None


class TenantSettingsResponse(BaseModel):
    tenant_id: str
    tenant_name: str
    ai_enabled: bool
    flow_editing_enabled: bool
    gemini_model: str
    fallback_models: List[str] = Field(default_factory=list)
    available_models: List[str] = Field(default_factory=list)

    @classmethod
    def from_domain(cls, item: TenantSettings) -> "TenantSettingsResponse":
        return cls(**item.model_dump())


@router.get("/{tenant_id}/settings", response_model=TenantSettingsResponse)
async def get_tenant_settings(
    tenant_id: str,
    service: TenantSettingsService = Depends(tenant_settings_service_dependency),
) -> TenantSettingsResponse:
    settings = service.get_or_create(tenant_id)
    return TenantSettingsResponse.from_domain(settings)


@router.patch("/{tenant_id}/settings", response_model=TenantSettingsResponse)
async def patch_tenant_settings(
    tenant_id: str,
    payload: TenantSettingsPatchPayload,
    service: TenantSettingsService = Depends(tenant_settings_service_dependency),
) -> TenantSettingsResponse:
    updated = service.update(
        tenant_id,
        tenant_name=payload.tenant_name,
        ai_enabled=payload.ai_enabled,
        flow_editing_enabled=payload.flow_editing_enabled,
        gemini_model=payload.gemini_model,
        fallback_models=payload.fallback_models,
    )
    return TenantSettingsResponse.from_domain(updated)
