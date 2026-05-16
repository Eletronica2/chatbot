"""Proposal endpoints (super-admin only)."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.access import assert_superadmin
from app.domain.auth import AuthenticatedUser
from app.domain.proposal import PlanRecommendation, Proposal
from app.services.admin_audit_service import AdminAuditService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    lead_service_dependency,
    proposal_service_dependency,
)
from app.services.lead_service import LeadService
from app.services.proposal_service import ProposalService

router = APIRouter(tags=["Proposals"])


class ProposalCreatePayload(BaseModel):
    lead_id: int | None = None
    company_name: str = Field(..., min_length=2, max_length=190)
    contact_name: str = Field(..., min_length=2, max_length=160)
    contact_email: str = Field(..., min_length=5, max_length=190)
    contact_whatsapp: str | None = Field(default=None, max_length=32)
    plan: str = Field(..., min_length=2, max_length=50)
    monthly_value: Decimal
    setup_fee: Decimal = Decimal("0")
    monthly_message_limit: int = Field(default=1000, gt=0)
    included_items: list[str] = Field(default_factory=list)
    validity_days: int = Field(default=7, gt=0, le=180)
    status: str = Field(default="draft")
    notes: str | None = None


class ProposalPatchPayload(BaseModel):
    status: str | None = None
    notes: str | None = None
    monthly_value: Decimal | None = None
    setup_fee: Decimal | None = None
    monthly_message_limit: int | None = None
    included_items: list[str] | None = None
    validity_days: int | None = None
    plan: str | None = None


class ProposalResponse(BaseModel):
    id: str
    lead_id: str | None = None
    tenant_id: str | None = None
    company_name: str
    contact_name: str
    contact_email: str
    contact_whatsapp: str | None = None
    plan: str
    monthly_value: Decimal
    setup_fee: Decimal
    monthly_message_limit: int
    included_items: list[str]
    validity_days: int
    status: str
    notes: str | None = None
    created_by_user_id: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    @classmethod
    def from_domain(cls, proposal: Proposal) -> "ProposalResponse":
        return cls(**proposal.model_dump())


class PlanRecommendationResponse(BaseModel):
    plan: str
    plan_label: str
    monthly_value: Decimal
    setup_fee: Decimal
    monthly_message_limit: int
    included_items: list[str]
    rationale: str

    @classmethod
    def from_domain(cls, recommendation: PlanRecommendation) -> "PlanRecommendationResponse":
        return cls(**recommendation.model_dump())


class ConvertLeadPayload(BaseModel):
    tenant_id: str = Field(..., min_length=2, max_length=120)
    tenant_email: str = Field(..., min_length=5, max_length=190)
    owner_name: str = Field(..., min_length=2, max_length=160)
    owner_email: str = Field(..., min_length=5, max_length=190)
    plan: str = Field(default="starter", min_length=2, max_length=50)
    monthly_message_limit: int = Field(default=1000, gt=0)
    owner_password: str | None = Field(default=None, min_length=6, max_length=120)


class ConvertLeadResponse(BaseModel):
    tenant: dict[str, Any]
    invite_token: str | None = None
    invite_expires_at: datetime | None = None


@router.get("/api/v1/admin/proposals", response_model=list[ProposalResponse])
async def list_admin_proposals(
    lead_id: int | None = Query(default=None),
    status: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: ProposalService = Depends(proposal_service_dependency),
) -> list[ProposalResponse]:
    assert_superadmin(user)
    items = await service.list_proposals(
        lead_id=lead_id,
        status=status,
        limit=limit,
        offset=offset,
    )
    return [ProposalResponse.from_domain(item) for item in items]


@router.post("/api/v1/admin/proposals", response_model=ProposalResponse, status_code=201)
async def create_admin_proposal(
    payload: ProposalCreatePayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: ProposalService = Depends(proposal_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> ProposalResponse:
    assert_superadmin(user)
    try:
        actor_id: int | None = None
        try:
            actor_id = int(user.user_id) if user.user_id else None
        except (TypeError, ValueError):
            actor_id = None
        proposal = await service.create_proposal(
            lead_id=payload.lead_id,
            company_name=payload.company_name,
            contact_name=payload.contact_name,
            contact_email=payload.contact_email,
            contact_whatsapp=payload.contact_whatsapp,
            plan=payload.plan,
            monthly_value=payload.monthly_value,
            setup_fee=payload.setup_fee,
            monthly_message_limit=payload.monthly_message_limit,
            included_items=payload.included_items,
            validity_days=payload.validity_days,
            status=payload.status,
            notes=payload.notes,
            created_by_user_id=actor_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await audit_service.append(
        tenant_id=user.tenant_id,
        action="proposal.create",
        entity_type="proposal",
        entity_key=str(proposal.id),
        summary=f"Proposta {proposal.plan} criada para {proposal.company_name}",
        actor=user,
        metadata={
            "plan": proposal.plan,
            "lead_id": proposal.lead_id,
            "monthly_value": str(proposal.monthly_value),
        },
    )
    return ProposalResponse.from_domain(proposal)


@router.patch("/api/v1/admin/proposals/{proposal_id}", response_model=ProposalResponse)
async def patch_admin_proposal(
    proposal_id: int,
    payload: ProposalPatchPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: ProposalService = Depends(proposal_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> ProposalResponse:
    assert_superadmin(user)
    try:
        proposal = await service.update_proposal(
            proposal_id=proposal_id,
            status=payload.status,
            notes=payload.notes,
            monthly_value=payload.monthly_value,
            setup_fee=payload.setup_fee,
            monthly_message_limit=payload.monthly_message_limit,
            included_items=payload.included_items,
            validity_days=payload.validity_days,
            plan=payload.plan,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await audit_service.append(
        tenant_id=user.tenant_id,
        action="proposal.update",
        entity_type="proposal",
        entity_key=str(proposal.id),
        summary=f"Proposta {proposal.id} atualizada ({proposal.status})",
        actor=user,
        metadata={"status": proposal.status, "plan": proposal.plan},
    )
    return ProposalResponse.from_domain(proposal)


@router.get(
    "/api/v1/admin/leads/{lead_id}/recommendation",
    response_model=PlanRecommendationResponse,
)
async def get_lead_recommendation(
    lead_id: int,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    proposals: ProposalService = Depends(proposal_service_dependency),
    leads: LeadService = Depends(lead_service_dependency),
) -> PlanRecommendationResponse:
    assert_superadmin(user)
    # busca direta no repositorio para evitar full-scan via list_leads
    row = await leads.repository.get_by_id(lead_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Lead nao encontrado")
    recommendation = proposals.recommend_plan(row.get("monthly_volume"))
    return PlanRecommendationResponse.from_domain(recommendation)


@router.post(
    "/api/v1/admin/leads/{lead_id}/convert",
    response_model=ConvertLeadResponse,
)
async def convert_lead_endpoint(
    lead_id: int,
    payload: ConvertLeadPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: ProposalService = Depends(proposal_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> ConvertLeadResponse:
    assert_superadmin(user)
    try:
        result = await service.convert_lead_to_tenant(
            lead_id=lead_id,
            tenant_id=payload.tenant_id,
            tenant_email=payload.tenant_email,
            owner_name=payload.owner_name,
            owner_email=payload.owner_email,
            plan=payload.plan,
            monthly_message_limit=payload.monthly_message_limit,
            owner_password=payload.owner_password,
            invited_by_user_id=user.user_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await audit_service.append(
        tenant_id=user.tenant_id,
        action="lead.convert",
        entity_type="lead",
        entity_key=str(lead_id),
        summary=f"Lead {lead_id} convertido em empresa {payload.tenant_id}",
        actor=user,
        metadata={
            "tenant_id": payload.tenant_id,
            "plan": payload.plan,
            "monthly_message_limit": payload.monthly_message_limit,
        },
    )
    return ConvertLeadResponse(
        tenant=result.get("tenant", {}),
        invite_token=result.get("invite_token"),
        invite_expires_at=result.get("invite_expires_at"),
    )
