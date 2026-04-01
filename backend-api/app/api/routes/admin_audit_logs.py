"""Administrative audit trail endpoints."""
from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

from app.api.access import resolve_tenant_scope
from app.domain.admin_audit import AdminAuditEntry
from app.domain.auth import AuthenticatedUser
from app.services.admin_audit_service import AdminAuditService
from app.services.dependencies import admin_audit_service_dependency, authenticated_user_dependency

router = APIRouter(prefix="/api/v1/admin/audit-logs", tags=["Admin Audit Logs"])


class AdminAuditEntryResponse(BaseModel):
    audit_id: str
    tenant_id: str
    actor_user_id: str | None = None
    actor_email: str | None = None
    action: str
    entity_type: str
    entity_key: str
    summary: str
    metadata: dict | None = None
    created_at: datetime | None = None

    @classmethod
    def from_domain(cls, item: AdminAuditEntry) -> "AdminAuditEntryResponse":
        return cls(**item.model_dump())


@router.get("", response_model=list[AdminAuditEntryResponse])
async def list_admin_audit_logs(
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> list[AdminAuditEntryResponse]:
    target_tenant_id = resolve_tenant_scope(user, request)
    items = await service.list_by_tenant(target_tenant_id)
    return [AdminAuditEntryResponse.from_domain(item) for item in items]
