"""Service layer for landing-page lead capture."""
from __future__ import annotations

import json
import logging
import re
from datetime import datetime
from typing import Any

from app.config.settings import Settings
from app.domain.lead import Lead
from app.repositories.lead_repository import LeadRepository
from app.services.email_service import EmailService

logger = logging.getLogger(__name__)

_EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")
_DIGITS_RE = re.compile(r"\D+")
_ALLOWED_STATUSES = {"new", "contacted", "qualified", "won", "lost"}


def _normalize_whatsapp(value: str) -> str:
    digits = _DIGITS_RE.sub("", value or "")
    if not digits:
        return ""
    if len(digits) <= 11 and not digits.startswith("55"):
        digits = "55" + digits
    return digits


def _normalize_email(value: str) -> str:
    return (value or "").strip().lower()


def _row_to_lead(row: dict[str, Any]) -> Lead:
    metadata = row.get("metadata")
    if isinstance(metadata, (bytes, bytearray)):
        metadata = metadata.decode("utf-8", errors="ignore")
    if isinstance(metadata, str):
        try:
            metadata = json.loads(metadata)
        except json.JSONDecodeError:
            metadata = None
    return Lead(
        id=str(row["id"]),
        name=str(row.get("name") or ""),
        company=str(row.get("company") or ""),
        segment=row.get("segment"),
        email=str(row.get("email") or ""),
        whatsapp=str(row.get("whatsapp") or ""),
        objective=str(row.get("objective") or ""),
        monthly_volume=row.get("monthly_volume"),
        team_size=row.get("team_size"),
        current_tools=row.get("current_tools"),
        best_contact_time=row.get("best_contact_time"),
        source=str(row.get("source") or "landing"),
        status=str(row.get("status") or "new"),
        notes=row.get("notes"),
        assigned_to=str(row["assigned_to"]) if row.get("assigned_to") is not None else None,
        metadata=metadata if isinstance(metadata, dict) else None,
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
    )


class LeadService:
    def __init__(
        self,
        *,
        repository: LeadRepository,
        email_service: EmailService,
        settings: Settings,
    ) -> None:
        self.repository = repository
        self.email_service = email_service
        self.settings = settings

    async def create_lead(
        self,
        *,
        name: str,
        company: str,
        segment: str | None,
        email: str,
        whatsapp: str,
        objective: str,
        monthly_volume: str | None,
        team_size: str | None,
        current_tools: str | None,
        best_contact_time: str | None,
        source: str = "landing",
        metadata: dict[str, Any] | None = None,
    ) -> Lead:
        name = (name or "").strip()
        company = (company or "").strip()
        objective = (objective or "").strip()
        email_norm = _normalize_email(email)
        whatsapp_norm = _normalize_whatsapp(whatsapp or "")
        if not name or len(name) < 2:
            raise ValueError("Informe seu nome completo.")
        if not company:
            raise ValueError("Informe o nome da empresa.")
        if not _EMAIL_RE.match(email_norm):
            raise ValueError("E-mail invalido.")
        if not whatsapp_norm or len(whatsapp_norm) < 10:
            raise ValueError("WhatsApp invalido. Informe DDD + numero.")
        if not objective or len(objective) < 5:
            raise ValueError("Conte o que voce pretende automatizar no WhatsApp.")

        row = await self.repository.create(
            name=name,
            company=company,
            segment=(segment or None),
            email=email_norm,
            whatsapp=whatsapp_norm,
            objective=objective,
            monthly_volume=(monthly_volume or None),
            team_size=(team_size or None),
            current_tools=(current_tools or None),
            best_contact_time=(best_contact_time or None),
            source=(source or "landing").strip() or "landing",
            metadata=metadata,
        )
        if row is None:
            raise RuntimeError("Nao foi possivel salvar o lead.")
        lead = _row_to_lead(row)
        await self._notify_internal_team(lead)
        return lead

    async def list_leads(
        self,
        *,
        status: str | None = None,
        search: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[Lead]:
        rows = await self.repository.list_all(
            status=status,
            search=search,
            limit=limit,
            offset=offset,
        )
        return [_row_to_lead(row) for row in rows]

    async def get_status_summary(self) -> dict[str, int]:
        return await self.repository.count_by_status()

    async def update_lead(
        self,
        *,
        lead_id: int,
        status: str | None = None,
        notes: str | None = None,
        assigned_to: int | None = None,
    ) -> Lead:
        if status is not None and status not in _ALLOWED_STATUSES:
            raise ValueError(f"Status invalido: {status}")
        row = await self.repository.update_lead(
            lead_id=lead_id,
            status=status,
            notes=notes,
            assigned_to=assigned_to,
        )
        if row is None:
            raise ValueError("Lead nao encontrado")
        return _row_to_lead(row)

    async def _notify_internal_team(self, lead: Lead) -> None:
        recipient = (self.settings.BOOTSTRAP_COMPANY_ADMIN_EMAIL or "").strip()
        if not recipient or not self.email_service.configured:
            return
        subject = f"Novo lead Operada: {lead.company}"
        body = (
            f"Novo contato recebido em {datetime.utcnow().strftime('%d/%m/%Y %H:%M UTC')}.\n"
            f"Empresa: {lead.company}\n"
            f"Segmento: {lead.segment or '-'}\n"
            f"Contato: {lead.name}\n"
            f"E-mail: {lead.email}\n"
            f"WhatsApp: {lead.whatsapp}\n"
            f"Objetivo: {lead.objective}\n"
            f"Volume mensal: {lead.monthly_volume or '-'}\n"
            f"Ferramentas atuais: {lead.current_tools or '-'}\n"
            f"Melhor horario: {lead.best_contact_time or '-'}"
        )
        try:
            await self.email_service.send_billing_event_email(
                tenant_id=self.settings.BOOTSTRAP_COMPANY_TENANT_ID,
                tenant_name="Operada",
                to_email=recipient,
                subject=subject,
                body=body,
            )
        except Exception as exc:  # pragma: no cover - depends on SMTP
            logger.warning("Falha ao notificar time interno sobre lead %s: %s", lead.id, exc)
