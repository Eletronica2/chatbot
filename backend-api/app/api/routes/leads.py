"""Lead capture endpoints (public submission + superadmin management)."""
from __future__ import annotations

from datetime import datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.access import assert_superadmin
from app.domain.auth import AuthenticatedUser
from app.domain.lead import Lead
from app.services.admin_audit_service import AdminAuditService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    lead_service_dependency,
)
from app.services.lead_service import LeadService

router = APIRouter(tags=["Leads"])


class LeadCreatePayload(BaseModel):
    name: str = Field(..., min_length=2, max_length=160)
    company: str = Field(..., min_length=2, max_length=190)
    segment: str | None = Field(default=None, max_length=120)
    email: str = Field(..., min_length=5, max_length=190)
    whatsapp: str = Field(..., min_length=8, max_length=32)
    objective: str = Field(..., min_length=5)
    monthly_volume: str | None = Field(default=None, max_length=80)
    team_size: str | None = Field(default=None, max_length=80)
    current_tools: str | None = Field(default=None)
    best_contact_time: str | None = Field(default=None, max_length=80)
    source: str | None = Field(default=None, max_length=80)
    metadata: dict[str, Any] | None = None


class LeadPatchPayload(BaseModel):
    status: str | None = None
    notes: str | None = None
    assigned_to: int | None = None


class LeadResponse(BaseModel):
    id: str
    name: str
    company: str
    segment: str | None = None
    email: str
    whatsapp: str
    objective: str
    monthly_volume: str | None = None
    team_size: str | None = None
    current_tools: str | None = None
    best_contact_time: str | None = None
    source: str = "landing"
    status: str = "new"
    notes: str | None = None
    assigned_to: str | None = None
    metadata: dict[str, Any] | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    @classmethod
    def from_domain(cls, lead: Lead) -> "LeadResponse":
        return cls(**lead.model_dump())


class LeadSummaryResponse(BaseModel):
    total: int
    by_status: dict[str, int]


@router.post("/api/v1/public/leads", response_model=LeadResponse, status_code=201)
async def submit_public_lead(
    payload: LeadCreatePayload,
    service: LeadService = Depends(lead_service_dependency),
) -> LeadResponse:
    try:
        lead = await service.create_lead(
            name=payload.name,
            company=payload.company,
            segment=payload.segment,
            email=payload.email,
            whatsapp=payload.whatsapp,
            objective=payload.objective,
            monthly_volume=payload.monthly_volume,
            team_size=payload.team_size,
            current_tools=payload.current_tools,
            best_contact_time=payload.best_contact_time,
            source=payload.source or "landing",
            metadata=payload.metadata,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return LeadResponse.from_domain(lead)


@router.get("/api/v1/admin/leads", response_model=list[LeadResponse])
async def list_admin_leads(
    status: str | None = Query(default=None),
    search: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: LeadService = Depends(lead_service_dependency),
) -> list[LeadResponse]:
    assert_superadmin(user)
    items = await service.list_leads(
        status=status,
        search=search,
        limit=limit,
        offset=offset,
    )
    return [LeadResponse.from_domain(item) for item in items]


@router.get("/api/v1/admin/leads/summary", response_model=LeadSummaryResponse)
async def admin_leads_summary(
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: LeadService = Depends(lead_service_dependency),
) -> LeadSummaryResponse:
    assert_superadmin(user)
    breakdown = await service.get_status_summary()
    total = sum(breakdown.values())
    return LeadSummaryResponse(total=total, by_status=breakdown)


@router.patch("/api/v1/admin/leads/{lead_id}", response_model=LeadResponse)
async def patch_admin_lead(
    lead_id: int,
    payload: LeadPatchPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: LeadService = Depends(lead_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> LeadResponse:
    assert_superadmin(user)
    try:
        lead = await service.update_lead(
            lead_id=lead_id,
            status=payload.status,
            notes=payload.notes,
            assigned_to=payload.assigned_to,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await audit_service.append(
        tenant_id=user.tenant_id,
        action="lead.update",
        entity_type="lead",
        entity_key=str(lead.id),
        summary=f"Lead {lead.company} atualizado",
        actor=user,
        metadata={
            "status": lead.status,
            "assigned_to": lead.assigned_to,
        },
    )
    return LeadResponse.from_domain(lead)
