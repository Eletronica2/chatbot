"""Subscription management endpoints for SaaS tenants."""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field

from app.api.access import assert_superadmin, resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.domain.subscription import TenantSubscription
from app.services.admin_audit_service import AdminAuditService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    subscription_service_dependency,
)
from app.services.subscription_service import SubscriptionService

router = APIRouter(prefix="/api/v1/subscriptions", tags=["Subscriptions"])


class SubscriptionPatchPayload(BaseModel):
    plan: Optional[str] = None
    status: Optional[str] = None
    renewal_date: Optional[datetime] = None
    monthly_message_limit: Optional[int] = Field(default=None, ge=0)


class SubscriptionResponse(BaseModel):
    tenant_id: str
    plan: str
    status: str
    renewal_date: datetime
    monthly_message_limit: int
    active: bool = Field(default=False)
    used_messages: int = Field(default=0)
    remaining_messages: int = Field(default=0)

    @classmethod
    def from_domain(
        cls,
        item: TenantSubscription,
        *,
        used_messages: int,
        remaining_messages: int,
    ) -> "SubscriptionResponse":
        return cls(
            tenant_id=item.tenant_id,
            plan=item.plan,
            status=item.status,
            renewal_date=item.renewal_date,
            monthly_message_limit=item.monthly_message_limit,
            active=item.is_valid(),
            used_messages=used_messages,
            remaining_messages=remaining_messages,
        )


@router.get("/{tenant_id}", response_model=SubscriptionResponse)
async def get_subscription(
    request: Request,
    tenant_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: SubscriptionService = Depends(subscription_service_dependency),
) -> SubscriptionResponse:
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    item = await service.get_or_create(target_tenant_id)
    usage = await service.get_usage_snapshot(target_tenant_id)
    return SubscriptionResponse.from_domain(
        item,
        used_messages=int(usage["used_messages"]),
        remaining_messages=int(usage["remaining_messages"]),
    )


@router.patch("/{tenant_id}", response_model=SubscriptionResponse)
async def patch_subscription(
    request: Request,
    tenant_id: str,
    payload: SubscriptionPatchPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: SubscriptionService = Depends(subscription_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> SubscriptionResponse:
    assert_superadmin(user)
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    item = await service.update(
        target_tenant_id,
        plan=payload.plan,
        status=payload.status,
        renewal_date=payload.renewal_date,
        monthly_message_limit=payload.monthly_message_limit,
    )
    await audit_service.append(
        tenant_id=target_tenant_id,
        action="subscription.update",
        entity_type="subscription",
        entity_key=target_tenant_id,
        summary=f"Plano atualizado para {item.plan}",
        actor=user,
        metadata={
            "status": item.status,
            "monthly_message_limit": item.monthly_message_limit,
            "renewal_date": item.renewal_date.isoformat(),
        },
    )
    usage = await service.get_usage_snapshot(target_tenant_id)
    return SubscriptionResponse.from_domain(
        item,
        used_messages=int(usage["used_messages"]),
        remaining_messages=int(usage["remaining_messages"]),
    )

