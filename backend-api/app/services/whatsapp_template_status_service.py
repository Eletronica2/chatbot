"""Apply Meta template status webhooks and serve watch snapshots."""
from __future__ import annotations

import hashlib
import logging
from typing import Any

from app.repositories.whatsapp_template_status_repository import WhatsAppTemplateStatusRepository
from app.services.template_status_logic import normalize_status
from app.services.whatsapp_account_service import WhatsAppAccountService

logger = logging.getLogger(__name__)


class WhatsAppTemplateStatusService:
    def __init__(
        self,
        repository: WhatsAppTemplateStatusRepository,
        whatsapp_account_service: WhatsAppAccountService,
    ):
        self.repository = repository
        self.whatsapp_account_service = whatsapp_account_service

    async def resolve_tenant_for_waba(self, waba_id: str) -> tuple[str, str] | None:
        resolved = await self.whatsapp_account_service.resolve_for_waba_id(waba_id)
        if resolved is None:
            return None
        return resolved.account.tenant_id, resolved.account.account_key

    @staticmethod
    def _dedupe_key(*, waba_id: str, template_id: str, event: str, event_time: int) -> str:
        raw = f"{waba_id}:{template_id}:{event}:{event_time}"
        return hashlib.sha256(raw.encode()).hexdigest()

    async def ingest_webhook(
        self,
        *,
        waba_id: str,
        entry_time: int,
        value: dict[str, Any],
    ) -> dict[str, Any]:
        waba = waba_id.strip()
        if not waba:
            return {"applied": False, "reason": "missing_waba"}

        resolved = await self.resolve_tenant_for_waba(waba)
        if resolved is None:
            logger.warning("template status webhook: unknown waba=%s", waba)
            return {"applied": False, "reason": "unknown_waba"}

        tenant_id, account_key = resolved
        if account_key != waba:
            logger.warning(
                "template status webhook: waba mismatch account_key=%s entry=%s tenant=%s",
                account_key,
                waba,
                tenant_id,
            )
            return {"applied": False, "reason": "waba_mismatch"}

        event = normalize_status(str(value.get("event") or value.get("status") or "PENDING"))
        template_id = str(
            value.get("message_template_id") or value.get("template_id") or value.get("id") or ""
        ).strip() or None
        name = str(value.get("message_template_name") or value.get("name") or "").strip()
        language = str(
            value.get("message_template_language") or value.get("language") or "pt_BR"
        ).strip()
        reason = value.get("reason") or value.get("rejected_reason")
        if reason is not None:
            reason = str(reason).strip()
            if reason.upper() == "NONE":
                reason = None

        if not name and not template_id:
            return {"applied": False, "reason": "missing_template_identity"}

        event_time = int(entry_time or 0)
        if event_time <= 0:
            import time

            event_time = int(time.time())

        dedupe = self._dedupe_key(
            waba_id=waba,
            template_id=template_id or name,
            event=event,
            event_time=event_time,
        )
        return await self.repository.apply_webhook(
            tenant_id=tenant_id,
            account_key=account_key,
            template_id=template_id,
            template_name=name or template_id or "unknown",
            language=language,
            status=event,
            rejected_reason=reason,
            event_time=event_time,
            dedupe_key=dedupe,
        )

    async def sync_graph_templates(
        self,
        *,
        tenant_id: str,
        account_key: str,
        templates: list[Any],
    ) -> None:
        rows = [
            {
                "name": t.name,
                "language": t.language,
                "status": t.status,
                "template_id": t.template_id,
                "rejected_reason": getattr(t, "rejected_reason", None),
            }
            for t in templates
        ]
        await self.repository.sync_from_graph_rows(
            tenant_id=tenant_id,
            account_key=account_key,
            rows=rows,
        )

    async def list_watch(
        self,
        *,
        tenant_id: str,
        account_key: str,
        since_unix: int,
    ) -> list[dict[str, Any]]:
        return await self.repository.list_watch(
            tenant_id=tenant_id,
            account_key=account_key,
            since_unix=since_unix,
        )