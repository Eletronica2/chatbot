"""Backoffice endpoints to provision SaaS tenants."""
from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.api.access import assert_superadmin
from app.domain.auth import AuthenticatedUser
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    tenant_admin_service_dependency,
)
from app.services.admin_audit_service import AdminAuditService
from app.services.tenant_admin_service import TenantAdminService, TenantProvisionRecord

router = APIRouter(prefix='/api/v1/admin/tenants', tags=['Admin Tenants'])


class TenantCreatePayload(BaseModel):
    tenant_id: str = Field(..., min_length=3)
    name: str = Field(..., min_length=2)
    email: str = Field(..., min_length=5)
    owner_name: str = Field(..., min_length=2)
    owner_email: str = Field(..., min_length=5)
    owner_password: str = Field(..., min_length=6)
    plan: str = Field(default='starter')
    monthly_message_limit: int | None = Field(default=None, ge=0)


class TenantSummaryResponse(BaseModel):
    tenant_id: str
    name: str
    email: str
    status: str
    plan: str
    owner_email: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    @classmethod
    def from_record(cls, item: TenantProvisionRecord) -> 'TenantSummaryResponse':
        return cls(
            tenant_id=item.tenant_id,
            name=item.name,
            email=item.email,
            status=item.status,
            plan=item.plan,
            owner_email=item.owner_email,
            created_at=item.created_at,
            updated_at=item.updated_at,
        )


@router.get('', response_model=list[TenantSummaryResponse])
async def list_tenants(
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: TenantAdminService = Depends(tenant_admin_service_dependency),
) -> list[TenantSummaryResponse]:
    assert_superadmin(user)
    items = await service.list_tenants()
    return [TenantSummaryResponse.from_record(item) for item in items]


@router.get('/{tenant_id}', response_model=TenantSummaryResponse)
async def get_tenant(
    tenant_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: TenantAdminService = Depends(tenant_admin_service_dependency),
) -> TenantSummaryResponse:
    assert_superadmin(user)
    try:
        item = await service.get_tenant(tenant_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return TenantSummaryResponse.from_record(item)


@router.post('', response_model=TenantSummaryResponse)
async def create_tenant(
    payload: TenantCreatePayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: TenantAdminService = Depends(tenant_admin_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> TenantSummaryResponse:
    assert_superadmin(user)
    try:
        item = await service.create_tenant(
            tenant_id=payload.tenant_id,
            name=payload.name,
            email=payload.email,
            owner_name=payload.owner_name,
            owner_email=payload.owner_email,
            owner_password=payload.owner_password,
            plan=payload.plan,
            monthly_message_limit=payload.monthly_message_limit,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await audit_service.append(
        tenant_id=item.tenant_id,
        action="tenant.create",
        entity_type="tenant",
        entity_key=item.tenant_id,
        summary=f"Tenant {item.name} criado",
        actor=user,
        metadata={"plan": item.plan, "owner_email": item.owner_email},
    )
    return TenantSummaryResponse.from_record(item)
