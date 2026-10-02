"""Proposal endpoints (super-admin only). New proposals use Billing Catalog V2."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.access import assert_superadmin
from app.domain.auth import AuthenticatedUser
from app.domain.proposal import PlanRecommendation, Proposal
from app.services.admin_audit_service import AdminAuditService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    email_service_dependency,
    lead_service_dependency,
    proposal_service_dependency,
)
from app.services.email_service import EmailService
from app.services.lead_service import LeadService
from app.services.proposal_service import MarginBlocked, ProposalService

router = APIRouter(tags=["Proposals"])

BillingModeLiteral = Literal["customer_direct", "solution_partner_credit_line"]


class ProposalCreatePayload(BaseModel):
    lead_id: int | None = None
    company_name: str = Field(..., min_length=2, max_length=190)
    contact_name: str = Field(..., min_length=2, max_length=160)
    contact_email: str = Field(..., min_length=5, max_length=190)
    contact_whatsapp: str | None = Field(default=None, max_length=32)
    plan_code: str = Field(..., min_length=3, max_length=80)
    billing_mode: BillingModeLiteral | None = None
    monthly_value: Decimal
    setup_fee: Decimal = Decimal("0")
    monthly_message_limit: int = Field(..., gt=0)
    operational_volume: int | None = Field(default=None, ge=0)
    marketing_volume: int | None = Field(default=None, ge=0)
    included_items: list[str] = Field(default_factory=list)
    validity_days: int = Field(default=7, gt=0, le=180)
    status: str = Field(default="draft")
    notes: str | None = None
    margin_override_reason: str | None = Field(default=None, max_length=500)


class ProposalPatchPayload(BaseModel):
    status: str | None = None
    notes: str | None = None
    monthly_value: Decimal | None = None
    setup_fee: Decimal | None = None
    monthly_message_limit: int | None = None
    included_items: list[str] | None = None
    validity_days: int | None = None
    plan: str | None = None
    margin_override_reason: str | None = Field(default=None, max_length=500)


class ProposalResponse(BaseModel):
    id: str
    lead_id: str | None = None
    tenant_id: str | None = None
    company_name: str
    contact_name: str
    contact_email: str
    contact_whatsapp: str | None = None
    plan: str
    catalog_version: str | None = None
    plan_code: str | None = None
    billing_mode: str | None = None
    is_legacy: bool = False
    monthly_value: Decimal
    setup_fee: Decimal
    monthly_message_limit: int
    operational_volume: int | None = None
    marketing_volume: int | None = None
    marketing_estimate: Decimal | None = None
    included_items: list[str]
    margin_snapshot: dict[str, Any] | None = None
    margin_override_reason: str | None = None
    validity_days: int
    status: str
    notes: str | None = None
    created_by_user_id: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    @classmethod
    def from_domain(cls, proposal: Proposal) -> "ProposalResponse":
        data = proposal.model_dump(exclude={"pricing_snapshot"})
        data["is_legacy"] = proposal.is_legacy
        return cls(**data)


class ConvertLeadPayload(BaseModel):
    tenant_id: str = Field(..., min_length=2, max_length=120)
    tenant_email: str = Field(..., min_length=5, max_length=190)
    owner_name: str = Field(..., min_length=2, max_length=160)
    owner_email: str = Field(..., min_length=5, max_length=190)
    plan_code: str = Field(..., min_length=3, max_length=80)
    billing_mode: BillingModeLiteral | None = None
    monthly_message_limit: int = Field(..., gt=0)
    monthly_price: Decimal | None = None
    owner_password: str | None = Field(default=None, min_length=6, max_length=120)
    margin_override_reason: str | None = Field(default=None, max_length=500)


class ConvertLeadResponse(BaseModel):
    tenant: dict[str, Any]
    billing: dict[str, Any] | None = None
    invite_token: str | None = None
    invite_expires_at: datetime | None = None
    invite_url: str | None = None
    email_status: str | None = None
    email_error: str | None = None
    owner_email: str | None = None
    owner_name: str | None = None
    owner_whatsapp: str | None = None


class RecommendationQuery(BaseModel):
    operational_answer: str | None = None
    marketing_answer: str | None = None
    billing_mode: BillingModeLiteral | None = None


class MarginCheckPayload(BaseModel):
    plan_code: str | None = None
    price: Decimal
    operational_units: int = Field(..., ge=0)
    billing_mode: BillingModeLiteral | None = None
    margin_override_reason: str | None = None


def _actor_int(user: AuthenticatedUser) -> int | None:
    try:
        return int(user.user_id) if user.user_id else None
    except (TypeError, ValueError):
        return None


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
    items = await service.list_proposals(lead_id=lead_id, status=status, limit=limit, offset=offset)
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
        proposal = await service.create_proposal(
            lead_id=payload.lead_id,
            company_name=payload.company_name,
            contact_name=payload.contact_name,
            contact_email=payload.contact_email,
            contact_whatsapp=payload.contact_whatsapp,
            plan_code=payload.plan_code,
            billing_mode=payload.billing_mode,
            monthly_value=payload.monthly_value,
            setup_fee=payload.setup_fee,
            monthly_message_limit=payload.monthly_message_limit,
            operational_volume=payload.operational_volume,
            marketing_volume=payload.marketing_volume,
            included_items=payload.included_items,
            validity_days=payload.validity_days,
            status=payload.status,
            notes=payload.notes,
            created_by_user_id=_actor_int(user),
            actor_user_id=user.user_id,
            margin_override_reason=payload.margin_override_reason,
        )
    except MarginBlocked as exc:
        raise HTTPException(status_code=422, detail={"code": "margin_guard", "message": str(exc)}) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    margin = proposal.margin_snapshot or {}
    await audit_service.append(
        tenant_id=user.tenant_id,
        action="proposal.create",
        entity_type="proposal",
        entity_key=str(proposal.id),
        summary=f"Proposta {proposal.plan_code} criada para {proposal.company_name}",
        actor=user,
        metadata={
            "plan_code": proposal.plan_code,
            "catalog_version": proposal.catalog_version,
            "billing_mode": proposal.billing_mode,
            "lead_id": proposal.lead_id,
            "monthly_value": str(proposal.monthly_value),
            "margin_status": margin.get("status"),
            "margin_percent": margin.get("margin_percent"),
        },
    )
    if proposal.margin_override_reason:
        await audit_service.append(
            tenant_id=user.tenant_id,
            action="proposal.margin_override",
            entity_type="proposal",
            entity_key=str(proposal.id),
            summary=f"Margem {margin.get('margin_percent')}% aprovada com justificativa",
            actor=user,
            metadata={
                "reason": proposal.margin_override_reason,
                "catalog_price": margin.get("catalog_price"),
                "new_value": str(proposal.monthly_value),
                "role": user.role,
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
        before = await service.get_proposal(proposal_id)
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
            actor_user_id=user.user_id,
            margin_override_reason=payload.margin_override_reason,
        )
    except MarginBlocked as exc:
        raise HTTPException(status_code=422, detail={"code": "margin_guard", "message": str(exc)}) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await audit_service.append(
        tenant_id=user.tenant_id,
        action="proposal.update",
        entity_type="proposal",
        entity_key=str(proposal.id),
        summary=f"Proposta {proposal.id} atualizada ({proposal.status})",
        actor=user,
        metadata={
            "status": proposal.status,
            "old_value": str(before.monthly_value),
            "new_value": str(proposal.monthly_value),
            "margin_override_reason": payload.margin_override_reason,
        },
    )
    return ProposalResponse.from_domain(proposal)


@router.get("/api/v1/admin/proposals/recommendation", response_model=PlanRecommendation)
async def get_recommendation(
    operational_answer: str | None = Query(default=None),
    marketing_answer: str | None = Query(default=None),
    billing_mode: BillingModeLiteral | None = Query(default=None),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    proposals: ProposalService = Depends(proposal_service_dependency),
) -> PlanRecommendation:
    assert_superadmin(user)
    return proposals.recommend(
        operational_answer=operational_answer, marketing_answer=marketing_answer, billing_mode=billing_mode
    )


@router.post("/api/v1/admin/proposals/margin-check")
async def proposal_margin_check(
    payload: MarginCheckPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    proposals: ProposalService = Depends(proposal_service_dependency),
) -> dict[str, Any]:
    assert_superadmin(user)
    return proposals.simulate_margin(
        price=payload.price,
        operational_units=payload.operational_units,
        billing_mode=payload.billing_mode or proposals._default_mode(),
        plan_code=payload.plan_code,
        discount_reason=payload.margin_override_reason,
    )


@router.get("/api/v1/admin/leads/{lead_id}/recommendation", response_model=PlanRecommendation)
async def get_lead_recommendation(
    lead_id: int,
    billing_mode: BillingModeLiteral | None = Query(default=None),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    proposals: ProposalService = Depends(proposal_service_dependency),
    leads: LeadService = Depends(lead_service_dependency),
) -> PlanRecommendation:
    assert_superadmin(user)
    row = await leads.repository.get_by_id(lead_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Lead nao encontrado")
    operational = row.get("operational_volume") or row.get("monthly_volume")
    return proposals.recommend(
        operational_answer=operational,
        marketing_answer=row.get("marketing_volume"),
        billing_mode=billing_mode,
    )


@router.post("/api/v1/admin/leads/{lead_id}/convert", response_model=ConvertLeadResponse)
async def convert_lead_endpoint(
    lead_id: int,
    payload: ConvertLeadPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: ProposalService = Depends(proposal_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
    email_service: EmailService = Depends(email_service_dependency),
) -> ConvertLeadResponse:
    assert_superadmin(user)
    try:
        result = await service.convert_lead_to_tenant(
            lead_id=lead_id,
            tenant_id=payload.tenant_id,
            tenant_email=payload.tenant_email,
            owner_name=payload.owner_name,
            owner_email=payload.owner_email,
            plan_code=payload.plan_code,
            billing_mode=payload.billing_mode,
            monthly_message_limit=payload.monthly_message_limit,
            monthly_price=payload.monthly_price,
            owner_password=payload.owner_password,
            invited_by_user_id=user.user_id,
            margin_override_reason=payload.margin_override_reason,
        )
    except MarginBlocked as exc:
        raise HTTPException(status_code=422, detail={"code": "margin_guard", "message": str(exc)}) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    tenant_info = result.get("tenant", {})
    invite = result.get("invite")
    email_status: str | None = None
    email_error: str | None = None
    if invite is not None:
        email_result = await email_service.send_invite_email(
            tenant_id=str(tenant_info.get("tenant_id") or payload.tenant_id),
            tenant_name=str(tenant_info.get("name") or payload.tenant_id),
            to_email=invite.user.email,
            display_name=invite.user.display_name,
            action_url=invite.action_url,
            expires_at=invite.expires_at,
        )
        email_status = email_result.status
        email_error = email_result.error
    await audit_service.append(
        tenant_id=user.tenant_id,
        action="lead.convert",
        entity_type="lead",
        entity_key=str(lead_id),
        summary=f"Lead {lead_id} convertido em empresa {payload.tenant_id}",
        actor=user,
        metadata={
            "tenant_id": payload.tenant_id,
            "plan_code": payload.plan_code,
            "billing_mode": payload.billing_mode,
            "monthly_message_limit": payload.monthly_message_limit,
            "monthly_price": str(payload.monthly_price) if payload.monthly_price is not None else None,
            "margin_override_reason": payload.margin_override_reason,
        },
    )
    billing = result.get("billing")
    return ConvertLeadResponse(
        tenant=tenant_info,
        billing={k: (str(v) if not isinstance(v, (dict, list, int, type(None))) else v) for k, v in (billing or {}).items()} or None,
        invite_token=result.get("invite_token"),
        invite_expires_at=result.get("invite_expires_at"),
        invite_url=invite.action_url if invite is not None else None,
        email_status=email_status,
        email_error=email_error,
        owner_email=payload.owner_email.strip().lower(),
        owner_name=payload.owner_name.strip(),
        owner_whatsapp=result.get("owner_whatsapp") or None,
    )
