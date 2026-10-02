"""Super-admin commercial proposals (Billing Catalog V2) + lead-to-tenant conversion."""
from __future__ import annotations

import json
import logging
import secrets
from decimal import ROUND_HALF_UP, Decimal
from typing import Any

from app.config.settings import settings
from app.domain.billing_v2 import (
    MSG_META_DIRECT,
    BillingMode,
    compute_margin,
    evaluate_discount,
    normalize_mode,
    parse_marketing_answer,
    parse_operational_answer,
)
from app.domain.proposal import PlanRecommendation, Proposal
from app.repositories.proposal_repository import ProposalRepository
from app.services.billing_gate import log_billing_event
from app.services.lead_service import LeadService
from app.services.tenant_admin_service import TenantAdminService
from app.services.tenant_user_service import TenantUserService

logger = logging.getLogger(__name__)

_SETUP_FEES = {
    "inicial": Decimal("497.00"),
    "essencial": Decimal("897.00"),
    "crescimento": Decimal("1497.00"),
    "profissional": Decimal("2497.00"),
    "empresarial": Decimal("4997.00"),
}

_FORBIDDEN_PHRASES = ("ilimitad", "meta inclusa", "tarifa meta inclusa")


class MarginBlocked(ValueError):
    """Proposal price violates the margin guard (loss, or <30% without reason)."""


def _brl(value: Decimal) -> str:
    q = value.quantize(Decimal("0.01"), ROUND_HALF_UP)
    whole, cents = f"{q:.2f}".split(".")
    whole = f"{int(whole):,}".replace(",", ".")
    return f"R$ {whole},{cents}"


def _thousands(value: int) -> str:
    return f"{value:,}".replace(",", ".")


def build_included_items(
    *,
    allowance: int | None,
    billing_mode: str,
    marketing_volume: int | None,
    marketing_unit_price: Decimal | None,
    topups: list[dict[str, Any]],
) -> list[str]:
    items = ["Plataforma Atende Ai", "IA para atendimento", "Automações e fluxos", "Painel de gestão"]
    if allowance:
        items.append(f"Até {_thousands(allowance)} mensagens operacionais entregues/mês")
    if topups:
        offers = " ou ".join(
            f"+{_thousands(int(t['operational_units']))} por {_brl(Decimal(t['price']))}" for t in topups if t.get("price")
        )
        if offers:
            items.append(f"Pacotes adicionais de mensagens operacionais: {offers}")
    if normalize_mode(billing_mode) == BillingMode.SOLUTION_PARTNER.value:
        if marketing_volume and marketing_unit_price is not None:
            estimate = marketing_unit_price * marketing_volume
            items.append(
                f"Campanhas estimadas: {_thousands(marketing_volume)} mensagens/mês ≈ {_brl(estimate)} "
                "(créditos de campanha pré-pagos)"
            )
        items.append("Campanhas são pré-pagas e o consumo considera mensagens entregues.")
    else:
        items.append("Tarifas da Meta: cobradas diretamente pela Meta conforme uso e categoria.")
    return items


def _assert_no_forbidden(items: list[str]) -> None:
    for item in items:
        folded = item.lower()
        if any(phrase in folded for phrase in _FORBIDDEN_PHRASES):
            raise ValueError(f"Texto proibido na proposta: {item!r}")


def _json_field(value: Any) -> Any:
    if isinstance(value, (bytes, bytearray)):
        value = value.decode("utf-8", errors="ignore")
    if isinstance(value, str):
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return None
    return value


def _row_to_proposal(row: dict[str, Any]) -> Proposal:
    items = _json_field(row.get("included_items"))
    if not isinstance(items, list):
        items = []
    return Proposal(
        id=str(row["id"]),
        lead_id=str(row["lead_id"]) if row.get("lead_id") is not None else None,
        tenant_id=str(row["tenant_id"]) if row.get("tenant_id") is not None else None,
        company_name=str(row.get("company_name") or ""),
        contact_name=str(row.get("contact_name") or ""),
        contact_email=str(row.get("contact_email") or ""),
        contact_whatsapp=row.get("contact_whatsapp"),
        plan=str(row.get("plan") or "starter"),
        catalog_version=row.get("catalog_version"),
        plan_code=row.get("plan_code"),
        billing_mode=row.get("billing_mode"),
        monthly_value=Decimal(str(row.get("monthly_value") or "0")),
        setup_fee=Decimal(str(row.get("setup_fee") or "0")),
        monthly_message_limit=int(row.get("monthly_message_limit") or 1000),
        operational_volume=row.get("operational_volume"),
        marketing_volume=row.get("marketing_volume"),
        marketing_estimate=Decimal(str(row["marketing_estimate"])) if row.get("marketing_estimate") is not None else None,
        included_items=[str(item) for item in items],
        pricing_snapshot=_json_field(row.get("pricing_snapshot")),
        margin_snapshot=_json_field(row.get("margin_snapshot")),
        margin_override_reason=row.get("margin_override_reason"),
        validity_days=int(row.get("validity_days") or 7),
        status=str(row.get("status") or "draft"),
        notes=row.get("notes"),
        created_by_user_id=str(row["created_by_user_id"]) if row.get("created_by_user_id") is not None else None,
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
    )


class ProposalService:
    def __init__(
        self,
        *,
        repository: ProposalRepository,
        lead_service: LeadService,
        tenant_admin_service: TenantAdminService,
        tenant_user_service: TenantUserService,
        billing_catalog: Any | None = None,
        rate_engine: Any | None = None,
        billing_gate: Any | None = None,
    ) -> None:
        self.repository = repository
        self.lead_service = lead_service
        self.tenant_admin_service = tenant_admin_service
        self.tenant_user_service = tenant_user_service
        self.billing_catalog = billing_catalog
        self.rate_engine = rate_engine
        self.billing_gate = billing_gate

    def _default_mode(self) -> str:
        return normalize_mode(settings.META_BILLING_DEFAULT)

    # ---------------------------------------------------------------
    # Recomendação V2
    # ---------------------------------------------------------------
    def recommend(
        self,
        *,
        operational_answer: str | None,
        marketing_answer: str | None,
        billing_mode: str | None = None,
    ) -> PlanRecommendation:
        catalog = self.billing_catalog
        mode = normalize_mode(billing_mode, self._default_mode())
        operational = parse_operational_answer(operational_answer)
        marketing = parse_marketing_answer(marketing_answer)
        suggestion = catalog.suggest(operational)
        plan = suggestion.plan
        unit_price = catalog.marketing_unit_price()
        marketing_estimate = (
            (unit_price * marketing.volume).quantize(Decimal("0.01"), ROUND_HALF_UP)
            if unit_price is not None and marketing.volume
            else (Decimal("0.00") if marketing.volume == 0 else None)
        )
        topups = catalog.topup_offers()
        items = build_included_items(
            allowance=plan.operational_units,
            billing_mode=mode,
            marketing_volume=marketing.volume,
            marketing_unit_price=unit_price,
            topups=topups,
        )
        if plan.is_custom:
            rationale = (
                f"Volume operacional informado ({operational.raw or 'não informado'}) acima de 12.000/mês: "
                "plano Empresarial sob consulta — defina franquia e preço e valide no Margin Guard."
            )
        elif suggestion.warning:
            rationale = f"Volume operacional não informado: sugerido {plan.label}."
        else:
            rationale = (
                f"Volume operacional \"{operational.raw}\" cabe na franquia de "
                f"{_thousands(int(plan.operational_units or 0))} mensagens do plano {plan.label}."
            )
        if marketing.volume:
            rationale += " Campanhas são produto adicional pré-pago e não alteram o plano base."
        margin = None
        if plan.price is not None:
            margin = self.simulate_margin(price=plan.price, operational_units=int(plan.operational_units or 0), billing_mode=mode, plan_code=plan.code)
        return PlanRecommendation(
            plan=plan.plan_key,
            plan_code=plan.code,
            plan_label=plan.label,
            catalog_version=plan.catalog_version,
            billing_mode=mode,
            monthly_value=plan.price,
            is_custom=plan.is_custom,
            setup_fee=_SETUP_FEES.get(plan.plan_key, Decimal("0")),
            monthly_message_limit=plan.operational_units,
            operational_volume=operational.volume,
            operational_answer=operational.raw or None,
            marketing_volume=marketing.volume,
            marketing_answer=marketing.raw or None,
            marketing_unit_price=unit_price,
            marketing_estimate=marketing_estimate,
            included_items=items,
            rationale=rationale,
            warning=suggestion.warning,
            topup_offers=topups,
            margin=margin,
        )

    def simulate_margin(
        self,
        *,
        price: Decimal,
        operational_units: int,
        billing_mode: str,
        plan_code: str | None,
        discount_reason: str | None = None,
    ) -> dict[str, Any]:
        item = self.billing_catalog.get_item(plan_code) if plan_code else None
        catalog_price = Decimal(item["price"]) if item and item.get("price") else None
        worst = self.rate_engine.worst_case_operational(market=settings.BILLING_MARKET)
        result = compute_margin(
            price=price,
            billing_mode=billing_mode,
            operational_units=operational_units,
            worst_operational_rate=worst,
            costs=self.billing_catalog.cost_inputs(),
        )
        decision = evaluate_discount(margin=result, catalog_price=catalog_price, reason=discount_reason)
        data = result.as_dict()
        data.update(
            {
                "catalog_price": str(catalog_price) if catalog_price is not None else None,
                "worst_operational_rate": str(worst) if worst is not None else None,
                "operational_units": operational_units,
                "discount": {
                    "allowed": decision.allowed,
                    "requires_reason": decision.requires_reason,
                    "code": decision.code,
                    "message": decision.message,
                },
            }
        )
        return data

    def assert_plan_margin(
        self,
        *,
        plan_code: str,
        monthly_price: Decimal | None,
        operational_allowance: int | None,
        billing_mode: str | None,
        reason: str | None,
        action: str,
        actor: str | None,
    ) -> dict[str, Any]:
        """Margin guard for assigning a plan to a tenant (same red/yellow rules as proposals)."""
        item = self.billing_catalog.get_item(plan_code)
        if not item or item["kind"] != "plan":
            raise ValueError("Plano inexistente no catálogo V2")
        price = monthly_price if monthly_price is not None else (Decimal(item["price"]) if item.get("price") is not None else None)
        units = operational_allowance or item.get("operational_units")
        if price is None or not units:
            raise ValueError("Plano sob consulta exige mensalidade e franquia operacional")
        margin = self.simulate_margin(
            price=Decimal(price),
            operational_units=int(units),
            billing_mode=normalize_mode(billing_mode, self._default_mode()),
            plan_code=plan_code,
            discount_reason=reason,
        )
        self._log_margin_warning(margin, action=action, plan_code=plan_code, actor=actor)
        if not margin["discount"]["allowed"]:
            raise MarginBlocked(margin["discount"]["message"])
        return margin

    @staticmethod
    def _log_margin_warning(margin: dict[str, Any], *, action: str, plan_code: str | None, actor: str | None) -> None:
        if margin.get("status") not in ("red", "yellow"):
            return
        log_billing_event(
            "billing.margin_warning",
            action=action, plan=plan_code, status=margin.get("status"), margin_percent=margin.get("margin_percent"),
            allowed=margin["discount"]["allowed"], code=margin["discount"]["code"], actor=actor,
        )

    # ---------------------------------------------------------------
    # CRUD
    # ---------------------------------------------------------------
    async def create_proposal(
        self,
        *,
        lead_id: int | None,
        company_name: str,
        contact_name: str,
        contact_email: str,
        contact_whatsapp: str | None,
        plan_code: str,
        billing_mode: str | None,
        monthly_value: Decimal,
        setup_fee: Decimal,
        monthly_message_limit: int,
        operational_volume: int | None,
        marketing_volume: int | None,
        included_items: list[str] | None,
        validity_days: int,
        status: str,
        notes: str | None,
        created_by_user_id: int | None,
        actor_user_id: str | None,
        margin_override_reason: str | None,
    ) -> Proposal:
        if not company_name.strip():
            raise ValueError("company_name obrigatorio")
        if monthly_value < 0 or setup_fee < 0:
            raise ValueError("Valores monetarios nao podem ser negativos")
        if monthly_message_limit <= 0:
            raise ValueError("Franquia operacional deve ser maior que zero")
        item = self.billing_catalog.get_item(plan_code)
        if not item or item["kind"] != "plan":
            raise ValueError("Plano inexistente no catálogo V2")
        if item["status"] != "active":
            raise ValueError("Plano legado não pode ser usado em novas propostas")
        mode = normalize_mode(billing_mode, self._default_mode())
        margin = self.simulate_margin(
            price=monthly_value,
            operational_units=int(monthly_message_limit),
            billing_mode=mode,
            plan_code=plan_code,
            discount_reason=margin_override_reason,
        )
        discount = margin["discount"]
        self._log_margin_warning(margin, action="proposal.create", plan_code=plan_code, actor=actor_user_id)
        if not discount["allowed"]:
            raise MarginBlocked(discount["message"])
        unit_price = self.billing_catalog.marketing_unit_price()
        marketing_estimate = (
            (unit_price * marketing_volume).quantize(Decimal("0.01"), ROUND_HALF_UP)
            if unit_price is not None and marketing_volume
            else None
        )
        topups = self.billing_catalog.topup_offers()
        items = [i for i in (included_items or []) if str(i).strip()] or build_included_items(
            allowance=int(monthly_message_limit),
            billing_mode=mode,
            marketing_volume=marketing_volume,
            marketing_unit_price=unit_price,
            topups=topups,
        )
        _assert_no_forbidden(items)
        rate_card = self.rate_engine.resolve("UTILITY", market=settings.BILLING_MARKET)
        pricing_snapshot = {
            "catalog_item": item,
            "monthly_value": str(monthly_value),
            "operational_allowance": int(monthly_message_limit),
            "topups": topups,
            "marketing_unit_price": str(unit_price) if unit_price is not None else None,
            "marketing_pack_offers": self.billing_catalog.marketing_pack_offers(),
            "rate_card_version": rate_card.version_code if rate_card else None,
            "rate_needs_review": bool(rate_card.needs_review) if rate_card else True,
        }
        override = (margin_override_reason or "").strip() or None
        row = await self.repository.create(
            lead_id=lead_id,
            tenant_id=None,
            company_name=company_name.strip(),
            contact_name=contact_name.strip(),
            contact_email=contact_email.strip().lower(),
            contact_whatsapp=(contact_whatsapp or "").strip() or None,
            plan=item["plan_key"] or plan_code,
            monthly_value=monthly_value,
            setup_fee=setup_fee,
            monthly_message_limit=int(monthly_message_limit),
            included_items=items,
            validity_days=int(validity_days or 7),
            status=status,
            notes=(notes or None),
            created_by_user_id=created_by_user_id,
            catalog_version=item["catalog_version"],
            plan_code=plan_code,
            billing_mode=mode,
            operational_volume=operational_volume,
            marketing_volume=marketing_volume,
            marketing_estimate=marketing_estimate,
            pricing_snapshot=pricing_snapshot,
            margin_snapshot=margin,
            margin_override_reason=override if discount["requires_reason"] else None,
            margin_override_by=actor_user_id if (override and discount["requires_reason"]) else None,
        )
        if row is None:
            raise RuntimeError("Falha ao salvar proposta")
        return _row_to_proposal(row)

    async def list_proposals(
        self,
        *,
        lead_id: int | None = None,
        status: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[Proposal]:
        rows = await self.repository.list_all(lead_id=lead_id, status=status, limit=limit, offset=offset)
        return [_row_to_proposal(row) for row in rows]

    async def get_proposal(self, proposal_id: int) -> Proposal:
        row = await self.repository.get_by_id(proposal_id)
        if row is None:
            raise ValueError("Proposta nao encontrada")
        return _row_to_proposal(row)

    async def update_proposal(
        self,
        *,
        proposal_id: int,
        status: str | None = None,
        notes: str | None = None,
        monthly_value: Decimal | None = None,
        setup_fee: Decimal | None = None,
        monthly_message_limit: int | None = None,
        included_items: list[str] | None = None,
        validity_days: int | None = None,
        plan: str | None = None,
        actor_user_id: str | None = None,
        margin_override_reason: str | None = None,
    ) -> Proposal:
        current = await self.get_proposal(proposal_id)
        pricing_change = monthly_value is not None or monthly_message_limit is not None or plan is not None
        if pricing_change and current.is_legacy:
            raise ValueError("Proposta histórica (catálogo V1) não pode ter preço alterado; crie uma nova proposta V2")
        margin_snapshot = None
        override = None
        if pricing_change:
            margin_snapshot = self.simulate_margin(
                price=monthly_value if monthly_value is not None else current.monthly_value,
                operational_units=int(monthly_message_limit or current.monthly_message_limit),
                billing_mode=current.billing_mode or self._default_mode(),
                plan_code=current.plan_code,
                discount_reason=margin_override_reason,
            )
            self._log_margin_warning(margin_snapshot, action="proposal.update", plan_code=current.plan_code,
                                     actor=actor_user_id)
            if not margin_snapshot["discount"]["allowed"]:
                raise MarginBlocked(margin_snapshot["discount"]["message"])
            if margin_snapshot["discount"]["requires_reason"]:
                override = (margin_override_reason or "").strip() or None
        if included_items is not None:
            _assert_no_forbidden(included_items)
        row = await self.repository.update_proposal(
            proposal_id=proposal_id,
            status=status,
            notes=notes,
            monthly_value=monthly_value,
            setup_fee=setup_fee,
            monthly_message_limit=monthly_message_limit,
            included_items=included_items,
            validity_days=validity_days,
            plan=None,
            margin_snapshot=margin_snapshot,
            margin_override_reason=override,
            margin_override_by=actor_user_id if override else None,
        )
        if row is None:
            raise ValueError("Proposta nao encontrada")
        return _row_to_proposal(row)

    # ---------------------------------------------------------------
    # Conversão lead -> tenant
    # ---------------------------------------------------------------
    async def convert_lead_to_tenant(
        self,
        *,
        lead_id: int,
        tenant_id: str,
        tenant_email: str,
        owner_name: str,
        owner_email: str,
        plan_code: str,
        monthly_message_limit: int,
        billing_mode: str | None = None,
        monthly_price: Decimal | None = None,
        owner_password: str | None = None,
        invited_by_user_id: str | None = None,
        margin_override_reason: str | None = None,
    ) -> dict[str, Any]:
        lead = await self.lead_service.repository.get_by_id(lead_id)
        if lead is None:
            raise ValueError("Lead nao encontrado")
        item = self.billing_catalog.get_item(plan_code) if self.billing_catalog else None
        if not item or item["kind"] != "plan" or item["status"] != "active":
            raise ValueError("Plano V2 inválido para conversão")
        self.assert_plan_margin(
            plan_code=plan_code,
            monthly_price=monthly_price,
            operational_allowance=monthly_message_limit,
            billing_mode=billing_mode,
            reason=margin_override_reason,
            action="lead.convert",
            actor=invited_by_user_id,
        )

        password = (owner_password or secrets.token_urlsafe(12)).strip()
        if len(password) < 6:
            password = secrets.token_urlsafe(12)

        provision = await self.tenant_admin_service.create_tenant(
            tenant_id=tenant_id,
            name=str(lead.get("company") or "Empresa"),
            email=tenant_email,
            owner_name=owner_name,
            owner_email=owner_email,
            owner_password=password,
            plan=item["plan_key"] or "inicial",
            monthly_message_limit=monthly_message_limit,
        )

        billing_config: dict[str, Any] | None = None
        if self.billing_gate is not None:
            import asyncio

            tenant_pk = self.billing_gate.tenant_pk(provision.tenant_id)
            billing_config = await asyncio.to_thread(
                self.billing_gate.configure_plan,
                tenant_pk,
                plan_code=plan_code,
                actor_id=invited_by_user_id,
                billing_mode=billing_mode,
                operational_allowance=monthly_message_limit,
                monthly_price=monthly_price,
            )
            billing_config.pop("before", None)

        invite = None
        if owner_password is None:
            try:
                invite = await self.tenant_user_service.invite_existing_user(
                    tenant_id=provision.tenant_id,
                    email=owner_email,
                    created_by_user_id=invited_by_user_id,
                )
            except Exception as exc:
                logger.warning("Falha ao gerar invite para tenant %s: %s", tenant_id, exc)

        try:
            await self.lead_service.update_lead(lead_id=lead_id, status="won")
        except Exception as exc:
            logger.warning("Falha ao marcar lead %s como won: %s", lead_id, exc)

        return {
            "tenant": {
                "tenant_id": provision.tenant_id,
                "name": provision.name,
                "email": provision.email,
                "plan": provision.plan,
                "status": provision.status,
                "created_at": provision.created_at,
            },
            "billing": billing_config,
            "invite": invite,
            "invite_token": invite.token if invite is not None else None,
            "invite_expires_at": invite.expires_at if invite is not None else None,
            "owner_whatsapp": str(lead.get("whatsapp") or ""),
        }


__all__ = ["ProposalService", "MarginBlocked", "build_included_items", "MSG_META_DIRECT"]
