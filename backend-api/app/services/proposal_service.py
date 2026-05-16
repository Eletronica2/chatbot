"""Service for super-admin commercial proposals + lead-to-tenant conversion."""
from __future__ import annotations

import json
import logging
import re
import secrets
from decimal import Decimal
from typing import Any

from app.domain.proposal import PlanRecommendation, Proposal
from app.repositories.proposal_repository import ProposalRepository
from app.services.lead_service import LeadService
from app.services.tenant_admin_service import TenantAdminService
from app.services.tenant_user_service import TenantUserService

logger = logging.getLogger(__name__)


_PLAN_LABELS = {
    "starter": "Inicial",
    "growth_basic": "Crescimento Basico",
    "growth": "Crescimento",
    "pro": "Profissional",
    "enterprise": "Empresarial",
}


# Catalogo de planos com defaults editaveis pelo super-admin no momento de
# emitir a proposta. Valores em BRL.
_PLAN_CATALOG: dict[str, dict[str, Any]] = {
    "starter": {
        "monthly_value": Decimal("197.00"),
        "setup_fee": Decimal("497.00"),
        "monthly_message_limit": 500,
        "included_items": [
            "Automacao base sob medida",
            "Atendimento humano integrado",
            "1 numero de WhatsApp Cloud API",
            "Suporte por e-mail (1 dia util)",
        ],
    },
    "growth_basic": {
        "monthly_value": Decimal("397.00"),
        "setup_fee": Decimal("897.00"),
        "monthly_message_limit": 2000,
        "included_items": [
            "Automacao base + 1 acao personalizada",
            "Treinamento da equipe (1h)",
            "1 numero de WhatsApp Cloud API",
            "Suporte por e-mail e WhatsApp",
        ],
    },
    "growth": {
        "monthly_value": Decimal("697.00"),
        "setup_fee": Decimal("1497.00"),
        "monthly_message_limit": 5000,
        "included_items": [
            "Automacao base + 3 acoes personalizadas",
            "Treinamento da equipe (2h)",
            "Integracao HTTP com sistema do cliente",
            "Painel de metricas operacionais",
            "Suporte prioritario",
        ],
    },
    "pro": {
        "monthly_value": Decimal("1197.00"),
        "setup_fee": Decimal("2497.00"),
        "monthly_message_limit": 20000,
        "included_items": [
            "Automacao base + acoes ilimitadas",
            "Treinamento da equipe (4h)",
            "Integracoes HTTP e webhooks",
            "Dashboards operacionais avancados",
            "Suporte prioritario com SLA",
        ],
    },
    "enterprise": {
        "monthly_value": Decimal("2497.00"),
        "setup_fee": Decimal("4997.00"),
        "monthly_message_limit": 100000,
        "included_items": [
            "Implantacao consultiva dedicada",
            "Mapeamento e treinamento operacional",
            "Multiplos numeros e integracoes complexas",
            "Engenharia dedicada para customizacoes",
            "SLA contratual + onboarding presencial/remoto",
        ],
    },
}


_VOLUME_TO_PLAN: list[tuple[re.Pattern[str], str, str]] = [
    (re.compile(r"at[eé]\s*500", re.IGNORECASE), "starter", "Volume baixo, ideal para validar o canal."),
    (re.compile(r"500.*2", re.IGNORECASE), "growth_basic", "Volume crescente exige mais automacao."),
    (re.compile(r"2[\.\s]*000.*5", re.IGNORECASE), "growth", "Volume medio: precisa de personalizacao e metricas."),
    (re.compile(r"5[\.\s]*000.*20", re.IGNORECASE), "pro", "Operacao consolidada: automacao avancada."),
    (re.compile(r"mais\s*de\s*20", re.IGNORECASE), "enterprise", "Operacao em escala: implantacao dedicada."),
    (re.compile(r"20[\.\s]*000", re.IGNORECASE), "enterprise", "Operacao em escala: implantacao dedicada."),
]


def _row_to_proposal(row: dict[str, Any]) -> Proposal:
    items = row.get("included_items")
    if isinstance(items, (bytes, bytearray)):
        items = items.decode("utf-8", errors="ignore")
    if isinstance(items, str):
        try:
            items = json.loads(items)
        except json.JSONDecodeError:
            items = []
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
        monthly_value=Decimal(str(row.get("monthly_value") or "0")),
        setup_fee=Decimal(str(row.get("setup_fee") or "0")),
        monthly_message_limit=int(row.get("monthly_message_limit") or 1000),
        included_items=[str(item) for item in items],
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
    ) -> None:
        self.repository = repository
        self.lead_service = lead_service
        self.tenant_admin_service = tenant_admin_service
        self.tenant_user_service = tenant_user_service

    # ---------------------------------------------------------------
    # Recomendacao
    # ---------------------------------------------------------------
    def recommend_plan(self, monthly_volume: str | None) -> PlanRecommendation:
        volume = (monthly_volume or "").strip()
        plan_key = "starter"
        rationale = "Volume nao informado: comecamos pelo plano Inicial e ajustamos conforme necessidade."
        if volume:
            for pattern, candidate, why in _VOLUME_TO_PLAN:
                if pattern.search(volume):
                    plan_key = candidate
                    rationale = why
                    break

        config = _PLAN_CATALOG[plan_key]
        return PlanRecommendation(
            plan=plan_key,
            plan_label=_PLAN_LABELS.get(plan_key, plan_key),
            monthly_value=config["monthly_value"],
            setup_fee=config["setup_fee"],
            monthly_message_limit=config["monthly_message_limit"],
            included_items=list(config["included_items"]),
            rationale=rationale,
        )

    def plan_defaults(self, plan: str) -> dict[str, Any]:
        config = _PLAN_CATALOG.get(plan)
        if config is None:
            config = _PLAN_CATALOG["starter"]
        return {
            "plan": plan if plan in _PLAN_CATALOG else "starter",
            "plan_label": _PLAN_LABELS.get(plan, plan),
            "monthly_value": config["monthly_value"],
            "setup_fee": config["setup_fee"],
            "monthly_message_limit": config["monthly_message_limit"],
            "included_items": list(config["included_items"]),
        }

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
        plan: str,
        monthly_value: Decimal,
        setup_fee: Decimal,
        monthly_message_limit: int,
        included_items: list[str],
        validity_days: int,
        status: str,
        notes: str | None,
        created_by_user_id: int | None,
    ) -> Proposal:
        if not company_name.strip():
            raise ValueError("company_name obrigatorio")
        if monthly_value < 0 or setup_fee < 0:
            raise ValueError("Valores monetarios nao podem ser negativos")
        if monthly_message_limit <= 0:
            raise ValueError("monthly_message_limit deve ser maior que zero")
        row = await self.repository.create(
            lead_id=lead_id,
            tenant_id=None,
            company_name=company_name.strip(),
            contact_name=contact_name.strip(),
            contact_email=contact_email.strip().lower(),
            contact_whatsapp=(contact_whatsapp or "").strip() or None,
            plan=plan.strip() or "starter",
            monthly_value=monthly_value,
            setup_fee=setup_fee,
            monthly_message_limit=int(monthly_message_limit),
            included_items=included_items,
            validity_days=int(validity_days or 7),
            status=status,
            notes=(notes or None),
            created_by_user_id=created_by_user_id,
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
        rows = await self.repository.list_all(
            lead_id=lead_id,
            status=status,
            limit=limit,
            offset=offset,
        )
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
    ) -> Proposal:
        row = await self.repository.update_proposal(
            proposal_id=proposal_id,
            status=status,
            notes=notes,
            monthly_value=monthly_value,
            setup_fee=setup_fee,
            monthly_message_limit=monthly_message_limit,
            included_items=included_items,
            validity_days=validity_days,
            plan=plan,
        )
        if row is None:
            raise ValueError("Proposta nao encontrada")
        return _row_to_proposal(row)

    # ---------------------------------------------------------------
    # Conversao lead -> tenant
    # ---------------------------------------------------------------
    async def convert_lead_to_tenant(
        self,
        *,
        lead_id: int,
        tenant_id: str,
        tenant_email: str,
        owner_name: str,
        owner_email: str,
        plan: str,
        monthly_message_limit: int,
        owner_password: str | None = None,
        invited_by_user_id: str | None = None,
    ) -> dict[str, Any]:
        lead = await self.lead_service.repository.get_by_id(lead_id)
        if lead is None:
            raise ValueError("Lead nao encontrado")

        # Senha temporaria sera substituida quando o owner aceitar o invite.
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
            plan=plan,
            monthly_message_limit=monthly_message_limit,
        )

        invite = None
        try:
            invite = await self.tenant_user_service.invite_user(
                tenant_id=provision.tenant_id,
                email=owner_email,
                display_name=owner_name,
                role="owner",
                created_by_user_id=invited_by_user_id,
            )
        except ValueError:
            # Owner ja foi criado dentro de create_tenant — ignora erro de
            # duplicidade no invite e mantemos o cadastro.
            invite = None
        except Exception as exc:
            logger.warning("Falha ao gerar invite para tenant %s: %s", tenant_id, exc)

        # Marca o lead como `won` para sair do pipeline ativo.
        try:
            await self.lead_service.update_lead(
                lead_id=lead_id,
                status="won",
            )
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
            "invite_token": invite.token if invite is not None else None,
            "invite_expires_at": invite.expires_at if invite is not None else None,
        }
