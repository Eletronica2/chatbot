"""Billing V2 API: tenant billing, superadmin controls and internal gate callbacks."""
from __future__ import annotations

import asyncio
from datetime import date
from decimal import Decimal, InvalidOperation
from typing import Any, Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from app.api.access import assert_capability, assert_superadmin, resolve_tenant_scope
from app.config.settings import settings
from app.domain.auth import AuthenticatedUser
from app.domain.billing_v2 import (
    BILLING_MODES,
    compute_margin,
    compute_marketing_margin,
    evaluate_discount,
)
from app.services.admin_audit_service import AdminAuditService
from app.services.billing_dashboard_service import BillingDashboardService
from app.services.billing_gate import TenantNotFound
from app.services.billing_service import BillingService
from app.services.message_service import MessageService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    billing_service_dependency,
    message_service_dependency,
    get_billing_catalog_service,
    get_billing_gate,
    get_billing_topup_service,
    get_meta_rate_engine,
    internal_api_dependency,
    proposal_service_dependency,
    usage_ledger_service_dependency,
)
from app.services.proposal_service import MarginBlocked, ProposalService
from app.services.usage_ledger_service import UsageLedgerService

router = APIRouter(tags=["Billing V2"])


def _dec(value: Any, field: str) -> Decimal | None:
    if value is None or value == "":
        return None
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError) as exc:
        raise HTTPException(status_code=422, detail=f"{field} inválido") from exc


def _tenant_pk(tenant_id: str) -> int:
    try:
        return get_billing_gate().tenant_pk(tenant_id)
    except TenantNotFound as exc:
        raise HTTPException(status_code=404, detail="Tenant não encontrado") from exc


def _dashboard() -> BillingDashboardService:
    gate = get_billing_gate()
    return BillingDashboardService(gate.database, gate, get_billing_catalog_service())


def _require_reason(reason: str | None) -> str:
    cleaned = (reason or "").strip()
    if len(cleaned) < 5:
        raise HTTPException(status_code=422, detail="Motivo obrigatório (mínimo 5 caracteres)")
    return cleaned[:500]


# ============================================================ tenant
@router.get("/api/v1/billing/v2/summary")
async def tenant_summary(
    request: Request,
    tenant_id: Optional[str] = Query(default=None),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
) -> dict[str, Any]:
    assert_capability(user, "canManageBilling")
    scope = resolve_tenant_scope(user, request, tenant_id)
    _tenant_pk(scope)
    return await asyncio.to_thread(get_billing_gate().summary, scope)


@router.get("/api/v1/billing/v2/usage")
async def tenant_usage(
    request: Request,
    tenant_id: Optional[str] = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
) -> dict[str, Any]:
    assert_capability(user, "canManageBilling")
    scope = resolve_tenant_scope(user, request, tenant_id)
    tenant_pk = _tenant_pk(scope)
    rows = await asyncio.to_thread(
        get_billing_gate().database.fetch_all,
        """
        SELECT id, unit_type, units, category, category_source, billing_mode, source_path, status,
               last_provider_status, template_name, campaign_id, created_at, finalized_at
        FROM billing_reservations WHERE tenant_id=%s ORDER BY created_at DESC LIMIT %s
        """,
        (tenant_pk, limit),
    )
    return {"tenant_id": scope, "items": rows}


@router.get("/api/v1/billing/v2/ledger")
async def tenant_ledger(
    request: Request,
    tenant_id: Optional[str] = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
) -> dict[str, Any]:
    assert_capability(user, "canManageBilling")
    scope = resolve_tenant_scope(user, request, tenant_id)
    tenant_pk = _tenant_pk(scope)
    rows = await asyncio.to_thread(
        get_billing_gate().database.fetch_all,
        """
        SELECT id, entry_type, unit_type, units, billing_mode, category, reason, created_at
        FROM billing_ledger WHERE tenant_id=%s ORDER BY id DESC LIMIT %s
        """,
        (tenant_pk, limit),
    )
    return {"tenant_id": scope, "items": rows}


@router.get("/api/v1/billing/v2/topups")
async def tenant_topups(
    request: Request,
    tenant_id: Optional[str] = Query(default=None),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
) -> dict[str, Any]:
    assert_capability(user, "canManageBilling")
    scope = resolve_tenant_scope(user, request, tenant_id)
    tenant_pk = _tenant_pk(scope)
    catalog = get_billing_catalog_service()
    gate = get_billing_gate()
    config = await asyncio.to_thread(gate.get_config, tenant_pk)
    purchases = await asyncio.to_thread(get_billing_topup_service().list_purchases, tenant_pk)
    return {
        "tenant_id": scope,
        "billing_mode": config["effective_mode"],
        "operational_offers": await asyncio.to_thread(catalog.topup_offers) if config["is_v2_plan"] else [],
        "marketing_packs": (
            await asyncio.to_thread(catalog.marketing_pack_offers)
            if config["effective_mode"] == "solution_partner_credit_line"
            else []
        ),
        "purchases": purchases,
        "stripe_mode": "test",
    }


class TopupCheckoutPayload(BaseModel):
    item_code: str = Field(..., min_length=3, max_length=80)
    units: Optional[int] = Field(default=None, ge=1, le=1_000_000)
    tenant_id: Optional[str] = None


@router.post("/api/v1/billing/v2/topups/checkout")
async def tenant_topup_checkout(
    payload: TopupCheckoutPayload,
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    billing_service: BillingService = Depends(billing_service_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> dict[str, Any]:
    assert_capability(user, "canManageBilling")
    scope = resolve_tenant_scope(user, request, payload.tenant_id)
    tenant_pk = _tenant_pk(scope)
    try:
        purchase = await asyncio.to_thread(
            get_billing_topup_service().create_purchase,
            tenant_pk,
            item_code=payload.item_code,
            units=payload.units,
            actor_id=user.user_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    checkout = await billing_service.create_topup_checkout(tenant_id=scope, purchase=purchase)
    await audit.append(
        tenant_id=scope,
        action="billing.topup.checkout_created",
        entity_type="billing_topup_purchase",
        entity_key=purchase["id"],
        summary=f"Compra {purchase['catalog_item_code']} x{purchase['units']} criada (pendente)",
        actor=user,
        metadata={"total_amount": purchase["total_amount"], "stripe_status": checkout.get("status")},
    )
    return {"purchase": purchase, "checkout": checkout}


# ============================================================ superadmin
@router.get("/api/v1/admin/billing/tenants/{tenant_id}/config")
async def admin_tenant_config(tenant_id: str, user: AuthenticatedUser = Depends(authenticated_user_dependency)) -> dict[str, Any]:
    assert_superadmin(user)
    tenant_pk = _tenant_pk(tenant_id)
    gate = get_billing_gate()
    config = await asyncio.to_thread(gate.get_config, tenant_pk)
    return {
        "tenant_id": tenant_id,
        "config": config,
        "global_default_mode": gate.default_mode(),
        "billing_v2_enabled": gate.enabled,
        "available_modes": sorted(BILLING_MODES),
    }


class BillingModePayload(BaseModel):
    billing_mode: Optional[Literal["customer_direct", "solution_partner_credit_line"]] = None
    reason: str
    confirm: bool = False


@router.patch("/api/v1/admin/billing/tenants/{tenant_id}/billing-mode")
async def admin_set_billing_mode(
    tenant_id: str,
    payload: BillingModePayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> dict[str, Any]:
    assert_superadmin(user)
    if not payload.confirm:
        raise HTTPException(status_code=422, detail="Confirmação obrigatória para alterar o modo de cobrança")
    reason = _require_reason(payload.reason)
    tenant_pk = _tenant_pk(tenant_id)
    result = await asyncio.to_thread(get_billing_gate().set_mode, tenant_pk, payload.billing_mode, actor_id=user.user_id)
    await audit.append(
        tenant_id=tenant_id,
        action="billing.mode.changed",
        entity_type="tenant_billing_config",
        entity_key=tenant_id,
        summary=f"Modo de cobrança: {result['old_effective']} → {result['new_effective']}",
        actor=user,
        metadata={"old_value": result["old"], "new_value": result["new"], "reason": reason, "role": user.role},
    )
    return {"ok": True, **result}


class AssignPlanPayload(BaseModel):
    plan_code: str
    billing_mode: Optional[Literal["customer_direct", "solution_partner_credit_line"]] = None
    operational_allowance: Optional[int] = Field(default=None, ge=1)
    monthly_price: Optional[str] = None
    reason: str


@router.post("/api/v1/admin/billing/tenants/{tenant_id}/plan")
async def admin_assign_plan(
    tenant_id: str,
    payload: AssignPlanPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
    proposals: ProposalService = Depends(proposal_service_dependency),
) -> dict[str, Any]:
    assert_superadmin(user)
    reason = _require_reason(payload.reason)
    tenant_pk = _tenant_pk(tenant_id)
    try:
        margin = await asyncio.to_thread(
            proposals.assert_plan_margin,
            plan_code=payload.plan_code,
            monthly_price=_dec(payload.monthly_price, "monthly_price"),
            operational_allowance=payload.operational_allowance,
            billing_mode=payload.billing_mode,
            reason=reason,
            action="billing.plan.assign",
            actor=user.user_id,
        )
    except MarginBlocked as exc:
        raise HTTPException(status_code=422, detail={"code": "margin_guard", "message": str(exc)}) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    try:
        result = await asyncio.to_thread(
            get_billing_gate().configure_plan,
            tenant_pk,
            plan_code=payload.plan_code,
            actor_id=user.user_id,
            billing_mode=payload.billing_mode,
            operational_allowance=payload.operational_allowance,
            monthly_price=_dec(payload.monthly_price, "monthly_price"),
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    before = result.pop("before", {}) or {}
    await audit.append(
        tenant_id=tenant_id,
        action="billing.plan.changed",
        entity_type="tenant_billing_config",
        entity_key=tenant_id,
        summary=f"Plano: {before.get('plan_code') or 'legado'} → {payload.plan_code}",
        actor=user,
        metadata={
            "old_value": {"plan_code": before.get("plan_code"), "monthly_price": str(before.get("monthly_price")) if before.get("monthly_price") is not None else None},
            "new_value": {"plan_code": payload.plan_code, "monthly_price": result["monthly_price"], "operational_allowance": result["operational_allowance"]},
            "margin": {"status": margin.get("status"), "margin_percent": margin.get("margin_percent"), "code": margin["discount"]["code"]},
            "reason": reason,
            "role": user.role,
        },
    )
    return {"ok": True, **result}


class ManualGrantPayload(BaseModel):
    unit_type: Literal["operational", "marketing"]
    units: int = Field(..., ge=1, le=1_000_000)
    reason: str


@router.post("/api/v1/admin/billing/tenants/{tenant_id}/grants")
async def admin_manual_grant(
    tenant_id: str,
    payload: ManualGrantPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> dict[str, Any]:
    assert_superadmin(user)
    reason = _require_reason(payload.reason)
    tenant_pk = _tenant_pk(tenant_id)
    from uuid import uuid4

    result = await asyncio.to_thread(
        get_billing_gate().grant,
        tenant_pk,
        unit_type=payload.unit_type,
        units=payload.units,
        source="manual",
        grant_key=f"manual:{tenant_pk}:{uuid4()}",
        actor_id=user.user_id,
        reason=f"manual_grant: {reason}"[:255],
    )
    await audit.append(
        tenant_id=tenant_id,
        action="billing.credit.manual_grant",
        entity_type="billing_entitlement_bucket",
        entity_key=str(result.get("bucket_id")),
        summary=f"Concessão manual de {payload.units} unidades {payload.unit_type}",
        actor=user,
        metadata={"new_value": payload.units, "unit_type": payload.unit_type, "reason": reason, "role": user.role},
    )
    return {"ok": True, **result}


class ReasonPayload(BaseModel):
    reason: str


@router.post("/api/v1/admin/billing/purchases/{purchase_id}/mark-paid")
async def admin_mark_purchase_paid(
    purchase_id: str,
    payload: ReasonPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> dict[str, Any]:
    assert_superadmin(user)
    reason = _require_reason(payload.reason)
    service = get_billing_topup_service()
    purchase = await asyncio.to_thread(service.get_purchase, purchase_id)
    if purchase is None:
        raise HTTPException(status_code=404, detail="Compra não encontrada")
    row = await asyncio.to_thread(
        get_billing_gate().database.fetch_one,
        "SELECT t.external_key FROM billing_topup_purchases p JOIN tenants t ON t.id=p.tenant_id WHERE p.id=%s",
        (purchase_id,),
    )
    result = await asyncio.to_thread(
        service.mark_paid_and_grant, purchase_id, provider_payment_id=None, actor_id=user.user_id, reason=f"admin: {reason}"[:255]
    )
    await audit.append(
        tenant_id=str(row["external_key"]),
        action="billing.topup.marked_paid",
        entity_type="billing_topup_purchase",
        entity_key=purchase_id,
        summary=f"Compra {purchase['catalog_item_code']} marcada como paga manualmente",
        actor=user,
        metadata={"reason": reason, "created": result.get("created"), "role": user.role},
    )
    return {"ok": True, **result}


@router.get("/api/v1/admin/billing/tenants/{tenant_id}/dashboard")
async def admin_tenant_dashboard(tenant_id: str, user: AuthenticatedUser = Depends(authenticated_user_dependency)) -> dict[str, Any]:
    assert_superadmin(user)
    _tenant_pk(tenant_id)
    data = await asyncio.to_thread(_dashboard().tenant_dashboard, tenant_id)
    data["purchases"] = await asyncio.to_thread(get_billing_topup_service().list_purchases, _tenant_pk(tenant_id), 20)
    return data


@router.get("/api/v1/admin/billing/overview")
async def admin_billing_overview(user: AuthenticatedUser = Depends(authenticated_user_dependency)) -> dict[str, Any]:
    assert_superadmin(user)
    return {"tenants": await asyncio.to_thread(_dashboard().overview)}


@router.get("/api/v1/admin/billing/rate-cards")
async def admin_rate_cards(
    market: Optional[str] = Query(default=None),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
) -> dict[str, Any]:
    assert_superadmin(user)
    return {"rate_cards": await asyncio.to_thread(get_meta_rate_engine().list_cards, market=market)}


class RateItem(BaseModel):
    category: str
    unit_price: str
    free_allowance: int = 0
    allowance_scope: Optional[str] = None
    tier_min: int = 0
    tier_max: Optional[int] = None
    billing_basis: str = "per_delivered_message"
    notes: Optional[str] = None


class RateVersionPayload(BaseModel):
    version_code: str = Field(..., min_length=3, max_length=64)
    market: str = "BR"
    currency: str = "BRL"
    effective_from: date
    source_reference: Optional[str] = None
    source_checked_at: Optional[date] = None
    needs_review: bool = True
    notes: Optional[str] = None
    rates: list[RateItem]
    reason: str


@router.post("/api/v1/admin/billing/rate-cards")
async def admin_create_rate_version(
    payload: RateVersionPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> dict[str, Any]:
    assert_superadmin(user)
    reason = _require_reason(payload.reason)
    try:
        created = await asyncio.to_thread(get_meta_rate_engine().create_version, payload.model_dump())
    except (ValueError, InvalidOperation) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await audit.append(
        tenant_id=settings.DEFAULT_TENANT_ID,
        action="billing.rate_card.version_created",
        entity_type="meta_rate_card",
        entity_key=payload.version_code,
        summary=f"Nova vigência {payload.version_code} a partir de {payload.effective_from}",
        actor=user,
        metadata={"new_value": [r.model_dump() for r in payload.rates], "reason": reason, "role": user.role},
    )
    return {"ok": True, "created": created}


class RateReviewPayload(BaseModel):
    source_checked_at: date
    source_reference: Optional[str] = None
    reason: str


@router.post("/api/v1/admin/billing/rate-cards/{card_id}/reviewed")
async def admin_mark_rate_reviewed(
    card_id: int,
    payload: RateReviewPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> dict[str, Any]:
    assert_superadmin(user)
    reason = _require_reason(payload.reason)
    changed = await asyncio.to_thread(
        get_meta_rate_engine().mark_reviewed, card_id, source_checked_at=payload.source_checked_at, source_reference=payload.source_reference
    )
    if not changed:
        raise HTTPException(status_code=404, detail="Rate card não encontrado")
    await audit.append(
        tenant_id=settings.DEFAULT_TENANT_ID,
        action="billing.rate_card.reviewed",
        entity_type="meta_rate_card",
        entity_key=str(card_id),
        summary=f"Rate card {card_id} revisado contra fonte oficial",
        actor=user,
        metadata={"reason": reason, "source_checked_at": str(payload.source_checked_at), "role": user.role},
    )
    return {"ok": True}


@router.get("/api/v1/admin/billing/catalog")
async def admin_catalog(user: AuthenticatedUser = Depends(authenticated_user_dependency)) -> dict[str, Any]:
    assert_superadmin(user)
    catalog = get_billing_catalog_service()
    return {
        "items": await asyncio.to_thread(catalog.list_items, include_legacy=True),
        "marketing_packs": await asyncio.to_thread(catalog.marketing_pack_offers),
    }


@router.get("/api/v1/admin/billing/cost-config")
async def admin_cost_config(user: AuthenticatedUser = Depends(authenticated_user_dependency)) -> dict[str, Any]:
    assert_superadmin(user)
    return {"items": await asyncio.to_thread(get_billing_catalog_service().cost_config_rows)}


class CostConfigPayload(BaseModel):
    value: Optional[str] = None
    reason: str


@router.put("/api/v1/admin/billing/cost-config/{key}")
async def admin_update_cost_config(
    key: str,
    payload: CostConfigPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> dict[str, Any]:
    assert_superadmin(user)
    reason = _require_reason(payload.reason)
    try:
        result = await asyncio.to_thread(
            get_billing_catalog_service().update_cost_config, key, _dec(payload.value, "value"), actor_id=user.user_id
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await audit.append(
        tenant_id=settings.DEFAULT_TENANT_ID,
        action="billing.cost_config.changed",
        entity_type="billing_cost_config",
        entity_key=key,
        summary=f"Custo {key}: {result['old_value']} → {result['new_value']}",
        actor=user,
        metadata={**result, "reason": reason, "role": user.role},
    )
    return {"ok": True, **result}


class MarginSimulationPayload(BaseModel):
    plan_code: Optional[str] = None
    price: Optional[str] = None
    operational_units: Optional[int] = Field(default=None, ge=0)
    billing_mode: Literal["customer_direct", "solution_partner_credit_line"] = "customer_direct"
    marketing_units: int = Field(default=0, ge=0)
    discount_reason: Optional[str] = None


def simulate_margin(payload: MarginSimulationPayload) -> dict[str, Any]:
    catalog = get_billing_catalog_service()
    engine = get_meta_rate_engine()
    item = catalog.get_item(payload.plan_code) if payload.plan_code else None
    catalog_price = Decimal(item["price"]) if item and item.get("price") else None
    price = _dec(payload.price, "price") if payload.price else catalog_price
    if price is None:
        raise HTTPException(status_code=422, detail="Informe o preço (plano sob consulta)")
    units = payload.operational_units if payload.operational_units is not None else int((item or {}).get("operational_units") or 0)
    worst = engine.worst_case_operational(market=settings.BILLING_MARKET)
    costs = catalog.cost_inputs()
    margin = compute_margin(price=price, billing_mode=payload.billing_mode, operational_units=units, worst_operational_rate=worst, costs=costs)
    discount = evaluate_discount(margin=margin, catalog_price=catalog_price, reason=payload.discount_reason)
    marketing_card = engine.resolve("MARKETING", market=settings.BILLING_MARKET)
    marketing = compute_marketing_margin(
        unit_price=catalog.marketing_unit_price() or Decimal("0"),
        meta_marketing_rate=marketing_card.unit_price if marketing_card else None,
        billing_mode=payload.billing_mode,
        costs=costs,
        units=max(payload.marketing_units, 1),
    )
    return {
        "plan_code": payload.plan_code,
        "catalog_price": str(catalog_price) if catalog_price is not None else None,
        "operational_units": units,
        "worst_operational_rate": str(worst) if worst is not None else None,
        "rate_needs_review": True,
        "operational": margin.as_dict(),
        "discount": {"allowed": discount.allowed, "requires_reason": discount.requires_reason, "code": discount.code, "message": discount.message},
        "marketing": marketing,
    }


@router.post("/api/v1/admin/billing/margin-simulation")
async def admin_margin_simulation(
    payload: MarginSimulationPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
) -> dict[str, Any]:
    assert_superadmin(user)
    return await asyncio.to_thread(simulate_margin, payload)


@router.get("/api/v1/admin/billing/reconciliation")
async def admin_reconciliation(user: AuthenticatedUser = Depends(authenticated_user_dependency)) -> dict[str, Any]:
    assert_superadmin(user)
    rows = await asyncio.to_thread(
        get_billing_gate().database.fetch_all,
        """
        SELECT r.id, t.external_key AS tenant_id, r.status, r.category, r.billing_mode, r.source_path,
               r.provider_message_id, r.reconciliation_note, r.created_at
        FROM billing_reservations r JOIN tenants t ON t.id=r.tenant_id
        WHERE r.reconciliation_required=1 OR r.status='pending_reconciliation'
        ORDER BY r.created_at DESC LIMIT 200
        """,
    )
    return {"items": rows}


class ReconcilePayload(BaseModel):
    tenant_id: str
    action: Literal["commit", "release", "acknowledge"]
    reason: str


@router.post("/api/v1/admin/billing/reconciliation/{reservation_id}")
async def admin_reconcile(
    reservation_id: str,
    payload: ReconcilePayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> dict[str, Any]:
    assert_superadmin(user)
    reason = _require_reason(payload.reason)
    tenant_pk = _tenant_pk(payload.tenant_id)
    try:
        result = await asyncio.to_thread(
            get_billing_gate().resolve_reconciliation, tenant_pk, reservation_id, action=payload.action, actor_id=user.user_id, reason=reason
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await audit.append(
        tenant_id=payload.tenant_id,
        action="billing.reconciliation.resolved",
        entity_type="billing_reservation",
        entity_key=reservation_id,
        summary=f"Reconciliação {payload.action}: {result['before']} → {result['after']}",
        actor=user,
        metadata={"old_value": result["before"], "new_value": result["after"], "reason": reason, "role": user.role},
    )
    return {"ok": True, **result}


@router.post("/api/v1/admin/billing/reconciliation-run")
async def admin_reconciliation_run(user: AuthenticatedUser = Depends(authenticated_user_dependency)) -> dict[str, Any]:
    assert_superadmin(user)
    gate = get_billing_gate()
    expired = await asyncio.to_thread(gate.expire_buckets)
    stale = await asyncio.to_thread(gate.mark_stale_pending)
    return {"expired_units": expired, "stale_marked": stale}


# ============================================================ internal (gateway)
class AcceptedPayload(BaseModel):
    tenant_id: str
    reservation_id: str
    provider_message_id: str


@router.post("/api/v1/internal/billing/accepted", dependencies=[Depends(internal_api_dependency)])
async def internal_billing_accepted(payload: AcceptedPayload) -> dict[str, Any]:
    try:
        return await asyncio.to_thread(
            get_billing_gate().mark_accepted, payload.tenant_id, payload.reservation_id, payload.provider_message_id
        )
    except TenantNotFound as exc:
        raise HTTPException(status_code=404, detail="Tenant não encontrado") from exc


class ReleasePayload(BaseModel):
    tenant_id: str
    reservation_id: str
    reason: str = "send_failed"


@router.post("/api/v1/internal/billing/release", dependencies=[Depends(internal_api_dependency)])
async def internal_billing_release(payload: ReleasePayload) -> dict[str, Any]:
    try:
        return await asyncio.to_thread(get_billing_gate().release, payload.tenant_id, payload.reservation_id, reason=payload.reason[:120])
    except TenantNotFound as exc:
        raise HTTPException(status_code=404, detail="Tenant não encontrado") from exc


class StatusPayload(BaseModel):
    tenant_id: str
    provider_message_id: str
    status: str
    phone_number_id: Optional[str] = None
    pricing_category: Optional[str] = None
    pricing_billable: Optional[bool] = None
    error_code: Optional[str] = None


@router.post("/api/v1/internal/billing/status", dependencies=[Depends(internal_api_dependency)])
async def internal_billing_status(
    payload: StatusPayload,
    usage_service: UsageLedgerService = Depends(usage_ledger_service_dependency),
    billing_service: BillingService = Depends(billing_service_dependency),
    message_service: MessageService = Depends(message_service_dependency),
) -> dict[str, Any]:
    status = payload.status.strip().lower()
    try:
        from app.services.dependencies import get_whatsapp_campaign_service

        await get_whatsapp_campaign_service().apply_provider_status(
            payload.tenant_id,
            payload.provider_message_id,
            status,
            error_code=payload.error_code,
        )
    except RuntimeError:
        pass
    gate = get_billing_gate()
    is_v2_plan = False
    if gate.enabled:
        try:
            tenant_pk = await asyncio.to_thread(gate.tenant_pk, payload.tenant_id)
            is_v2_plan = bool((await asyncio.to_thread(gate.get_config, tenant_pk)).get("is_v2_plan"))
        except TenantNotFound:
            is_v2_plan = False
    if status == "delivered":
        legacy = await usage_service.record_delivered(payload.tenant_id, payload.provider_message_id, market="BR", quantity=1)
        # V2 packaged plans are prepaid; the legacy per-message meter would double charge.
        if legacy.get("created") and not is_v2_plan:
            await billing_service.report_meter_event(payload.tenant_id, payload.provider_message_id, quantity=1)
    if not gate.enabled:
        return {"ok": True, "billing_v2": False}
    result = await asyncio.to_thread(
        get_billing_gate().apply_status,
        payload.tenant_id,
        payload.provider_message_id,
        status,
        phone_number_id=payload.phone_number_id,
        pricing_category=payload.pricing_category,
        pricing_billable=payload.pricing_billable,
        error_code=payload.error_code,
    )
    if status == "failed" and payload.provider_message_id:
        await message_service.patch_metadata_by_external_message_id(
            tenant_id=payload.tenant_id,
            external_message_id=payload.provider_message_id,
            patch={
                "delivery_status": "failed",
                "delivery_error_code": payload.error_code,
            },
        )
    return result
