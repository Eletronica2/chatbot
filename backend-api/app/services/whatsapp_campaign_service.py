from __future__ import annotations

import asyncio
import json
import re
import uuid
from datetime import datetime
from typing import Any

from app.config.settings import settings
from app.domain.whatsapp_campaign import (
    CampaignCreate,
    CampaignDetail,
    CampaignPlanSnapshot,
    CampaignRecipientRow,
    CampaignSendReadiness,
    CampaignSummary,
    CampaignValidationResult,
)
from app.repositories.campaign_repository import CampaignRepository
from app.services.campaign_meta_estimate import (
    META_BILLING_DISCLAIMER,
    estimate_actual_spend,
    estimate_campaign_cost,
)
from app.services.campaign_metrics import presentation_counts
from app.services.campaign_xlsx import build_results_xlsx, build_template_xlsx, parse_destinatarios_xlsx
from app.services.meta_rate_engine import MetaRateEngine
from app.services.subscription_service import SubscriptionService
from app.services.whatsapp_template_service import WhatsAppTemplateService
from app.services.whatsapp_account_service import WhatsAppAccountService


class WhatsAppCampaignService:
    def __init__(
        self,
        repository: CampaignRepository,
        template_service: WhatsAppTemplateService,
        account_service: WhatsAppAccountService,
        *,
        subscription_service: SubscriptionService | None = None,
        meta_rate_engine: MetaRateEngine | None = None,
    ):
        self.repository = repository
        self.template_service = template_service
        self.account_service = account_service
        self.subscription_service = subscription_service
        self.meta_rate_engine = meta_rate_engine

    def _plan_snapshot_from_check(self, check) -> CampaignPlanSnapshot:
        sub = check.subscription
        return CampaignPlanSnapshot(
            plan=str(sub.plan or ""),
            status=str(sub.status or ""),
            used_messages=int(check.used_messages or 0),
            monthly_message_limit=int(sub.monthly_message_limit or 0),
            renewal_date=sub.renewal_date,
        )

    def _blocked_message(self, code: str | None, *, sub_status: str = "") -> str:
        status = (sub_status or "").strip().lower()
        if code == "campaign_disabled":
            return "Envios de campanha desativados neste ambiente (CAMPAIGN_SEND_ENABLED=false)."
        if code == "message_limit_reached":
            return "Limite mensal de uso do software Atende Ai atingido. Aguarde o próximo ciclo ou faça upgrade do plano."
        if code == "subscription_inactive":
            if status == "past_due":
                return (
                    "Assinatura Atende Ai em atraso (past_due). Regularize o plano para liberar disparos "
                    "(isso é independente da cobrança Meta no WhatsApp)."
                )
            if status == "canceled":
                return "Assinatura Atende Ai cancelada. Reative o plano para enviar campanhas."
            if status == "inactive":
                return "Plano Atende Ai inativo. Ative a assinatura para enviar campanhas."
            return "Plano Atende Ai inativo ou indisponível para envios."
        return "Envio não autorizado pelo plano Atende Ai."

    async def get_send_readiness(self, tenant_id: str) -> CampaignSendReadiness:
        allowed, code, message, snapshot = await self._sends_allowed(tenant_id)
        return CampaignSendReadiness(
            sends_enabled=allowed,
            sends_blocked_code=code,
            sends_blocked_reason=message,
            plan_snapshot=snapshot,
        )

    async def _sends_allowed(
        self, tenant_id: str
    ) -> tuple[bool, str | None, str | None, CampaignPlanSnapshot | None]:
        if not settings.CAMPAIGN_SEND_ENABLED:
            return False, "campaign_disabled", self._blocked_message("campaign_disabled"), None
        if self.subscription_service is None:
            return True, None, None, None
        check = await self.subscription_service.check_message_allowance(tenant_id)
        snapshot = self._plan_snapshot_from_check(check)
        if not check.allowed:
            code = check.reason or "subscription_inactive"
            msg = self._blocked_message(code, sub_status=snapshot.status)
            if code == "message_limit_reached":
                limit = snapshot.monthly_message_limit
                used = snapshot.used_messages
                if limit > 0:
                    msg = f"Limite mensal do plano atingido ({used}/{limit} mensagens processadas no mês)."
            return False, code, msg, snapshot
        return True, None, None, snapshot

    def _meta_estimate(self, category: str, count: int) -> dict[str, Any]:
        if self.meta_rate_engine is None:
            return {"recipients": count, "disclaimer": META_BILLING_DISCLAIMER, "is_official_invoice": False}
        return estimate_campaign_cost(
            rate_engine=self.meta_rate_engine,
            category=category,
            recipient_count=count,
        )

    @staticmethod
    def _var_keys_from_body(body: str | None) -> list[str]:
        if not body:
            return []
        named = re.findall(r"\{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\}", body or "")
        if named:
            return list(dict.fromkeys(named))
        nums = sorted({int(m) for m in re.findall(r"\{\{(\d+)\}\}", body or "")})
        return [str(n) for n in nums]

    @staticmethod
    def _body_params_list(body_text: str | None, params: dict[str, str]) -> list[str]:
        if not body_text:
            return []
        if re.search(r"\{\{\d+\}\}", body_text):
            nums = sorted({int(m) for m in re.findall(r"\{\{(\d+)\}\}", body_text)})
            return [str(params.get(str(n), params.get(n, ""))).strip() for n in nums]
        keys = re.findall(r"\{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\}", body_text)
        return [str(params.get(k, "")).strip() for k in dict.fromkeys(keys)]

    async def list_campaigns(self, tenant_id: str) -> list[CampaignSummary]:
        rows = await self.repository.list_campaigns(tenant_id)
        extras = await self.repository.accepted_exception_counts(tenant_id)
        out = []
        for row in rows:
            item = dict(row)
            extra = extras.get(int(item["id"]), {"failed": 0, "uncertain": 0})
            item["failed_accepted"] = extra["failed"]
            item["uncertain_accepted"] = extra["uncertain"]
            out.append(self._to_summary(item))
        return out

    async def create_campaign(self, tenant_id: str, payload: CampaignCreate, *, user_id: str | None) -> CampaignSummary:
        accounts = await self.account_service.list_accounts(tenant_id)
        account_key = payload.account_key or (accounts[0].account_key if accounts else None)
        selected = next((a for a in accounts if a.account_key == account_key), None)
        templates = await self.template_service.list_templates(tenant_id, account_key=account_key)
        tpl = next(
            (t for t in templates if t.name == payload.template_name and t.language == payload.template_language),
            None,
        )
        if tpl is None:
            raise ValueError("Template não encontrado")
        if tpl.status.upper() != "APPROVED":
            raise ValueError("Somente templates APPROVED podem ser usados em campanha")
        row = await self.repository.create_campaign(
            tenant_id=tenant_id,
            payload={
                "name": payload.name,
                "account_key": account_key,
                "phone_number_id": selected.phone_number_id if selected else None,
                "template_name": payload.template_name,
                "template_language": payload.template_language,
                "template_category": str(tpl.category or payload.template_category).upper(),
                "body_variable_keys": self._var_keys_from_body(tpl.body_text),
                "created_by_user_id": user_id,
            },
        )
        return self._to_summary(row)

    async def build_import_xlsx(self, tenant_id: str, campaign_key: str) -> bytes:
        row = await self._require_campaign(tenant_id, campaign_key)
        keys = json.loads(row.get("body_variable_keys") or "[]")
        if not isinstance(keys, list):
            keys = []
        templates = await self.template_service.list_templates(tenant_id, account_key=row.get("account_key"))
        tpl = next(
            (t for t in templates if t.name == row["template_name"] and t.language == row["template_language"]),
            None,
        )
        body = tpl.body_text if tpl else ""
        return build_template_xlsx(
            template_name=row["template_name"],
            category=row["template_category"],
            language=row["template_language"],
            body_example=body or "",
            variable_columns=[str(k) for k in keys],
        )

    async def validate_upload(self, tenant_id: str, campaign_key: str, raw: bytes) -> CampaignValidationResult:
        row = await self._require_campaign(tenant_id, campaign_key)
        if str(row.get("status") or "") in {"completed", "cancelled", "canceled", "running"}:
            raise ValueError("Esta campanha não aceita nova importação de destinatários")
        keys = json.loads(row.get("body_variable_keys") or "[]")
        if not isinstance(keys, list):
            keys = []
        parsed, parse_errors = parse_destinatarios_xlsx(raw, variable_columns=[str(k) for k in keys])
        valid = [p for p in parsed if not p.get("errors")]
        phones = [p["phone"] for p in valid]
        dup = len(phones) - len(set(phones))
        recipients_preview = [
            {
                "idempotency_key": f"camp:{campaign_key}:{p['phone']}",
                **p,
            }
            for p in parsed
        ]
        sends_enabled, blocked_code, blocked_reason, plan_snapshot = await self._sends_allowed(tenant_id)
        estimate = self._meta_estimate(str(row["template_category"]), len(valid))
        estimate["recipients"] = len(valid)
        estimate["category"] = row["template_category"]
        for item in recipients_preview:
            item["idempotency_key"] = f"camp:{campaign_key}:{item['phone']}"
        await self.repository.replace_recipients(
            tenant_id=tenant_id,
            campaign_id=int(row["id"]),
            rows=recipients_preview,
        )
        await self.repository.update_campaign(
            tenant_id,
            int(row["id"]),
            {
                "total_recipients": len(valid),
                "estimate_json": estimate,
                "meta_cost_estimate_json": estimate,
                "pending_count": len(valid),
                "status": "validated",
            },
        )
        from app.domain.whatsapp_campaign import CampaignRecipientPreview

        previews = [
            CampaignRecipientPreview(
                row_number=int(p["row_number"]),
                phone=str(p["phone"]),
                body_params=dict(p.get("body_params") or {}),
                consent_ok=bool(p.get("consent_ok")),
                errors=list(p.get("errors") or []),
            )
            for p in parsed
        ]
        invalid_rows = len([p for p in parsed if p.get("errors")])
        consent_missing = len([p for p in parsed if p.get("consent_denied")])
        return CampaignValidationResult(
            campaign_id=campaign_key,
            total_rows=len(parsed),
            valid_rows=len(valid),
            duplicate_phones=dup,
            invalid_rows=invalid_rows,
            consent_missing_rows=consent_missing,
            recipients=previews,
            errors=parse_errors,
            estimate=estimate,
            meta_disclaimer=META_BILLING_DISCLAIMER,
            sends_enabled=sends_enabled,
            sends_blocked_reason=blocked_reason,
            sends_blocked_code=blocked_code,
            plan_snapshot=plan_snapshot,
        )

    async def start_campaign(
        self,
        tenant_id: str,
        campaign_key: str,
        *,
        confirm: bool,
        recipient_authorization: bool = False,
    ) -> tuple[CampaignSummary, list[str]]:
        if not confirm:
            raise ValueError("Confirmação explícita obrigatória")
        if not recipient_authorization:
            raise ValueError("Declaração de autorização dos destinatários é obrigatória")
        row = await self._require_campaign(tenant_id, campaign_key)
        if row.get("status") not in {"validated", "paused"}:
            raise ValueError("Campanha não está validada")
        pending = await self.repository.list_pending_recipients(
            tenant_id=tenant_id, campaign_id=int(row["id"]), limit=5000
        )
        pending = [
            item
            for item in pending
            if "não autorizado" not in str(item.get("error_message") or "").lower()
        ]
        if not pending:
            raise ValueError("Nenhum destinatário pendente")
        authorized = [str(item.get("phone_e164") or "") for item in pending if item.get("phone_e164")]
        sends_ok, blocked_code, blocked, _snapshot = await self._sends_allowed(tenant_id)
        if not sends_ok:
            raise ValueError(blocked or "Envio não autorizado")
        now = datetime.utcnow()
        await self.repository.update_campaign(
            tenant_id,
            int(row["id"]),
            {"status": "running", "confirmed_at": now, "started_at": now},
        )
        row = await self.repository.get_campaign(tenant_id, campaign_key)
        return self._to_summary(row or {}), authorized

    async def pause_campaign(self, tenant_id: str, campaign_key: str) -> CampaignSummary:
        row = await self._require_campaign(tenant_id, campaign_key)
        await self.repository.update_campaign(
            tenant_id, int(row["id"]), {"status": "paused", "paused_at": datetime.utcnow()}
        )
        row = await self.repository.get_campaign(tenant_id, campaign_key)
        return self._to_summary(row or {})

    async def cancel_campaign(self, tenant_id: str, campaign_key: str) -> CampaignSummary:
        row = await self._require_campaign(tenant_id, campaign_key)
        await self.repository.update_campaign(
            tenant_id, int(row["id"]), {"status": "cancelled", "completed_at": datetime.utcnow()}
        )
        return self._to_summary((await self.repository.get_campaign(tenant_id, campaign_key)) or {})

    async def process_queue_tick(self, *, limit_per_campaign: int = 5) -> None:
        if not settings.CAMPAIGN_SEND_ENABLED:
            return
        running = await self.repository.running_campaigns(limit=3)
        for camp in running:
            tenant_id = str(camp.get("tenant_external_key") or "")
            campaign_key = str(camp.get("campaign_key") or "")
            await self.repository.reclaim_stale_sending(tenant_id=tenant_id, campaign_id=int(camp["id"]))
            pending = await self.repository.list_pending_recipients(
                tenant_id=tenant_id, campaign_id=int(camp["id"]), limit=limit_per_campaign
            )
            if not pending:
                await self.repository.refresh_campaign_counters(tenant_id, int(camp["id"]))
                await self._update_consumption_estimate(tenant_id, int(camp["id"]), camp)
                await self.repository.update_campaign(
                    tenant_id,
                    int(camp["id"]),
                    {"status": "completed", "completed_at": datetime.utcnow()},
                )
                continue
            templates = await self.template_service.list_templates(tenant_id, account_key=camp.get("account_key"))
            tpl = next(
                (t for t in templates if t.name == camp["template_name"] and t.language == camp["template_language"]),
                None,
            )
            if tpl is None or tpl.status.upper() != "APPROVED":
                await self.repository.update_campaign(tenant_id, int(camp["id"]), {"status": "failed"})
                continue
            for rec in pending:
                live = await self.repository.get_campaign(tenant_id, campaign_key)
                if live and str(live.get("status")) in {"paused", "cancelled"}:
                    break
                claimed = await self.repository.try_mark_sending(tenant_id, int(rec["id"]))
                if not claimed:
                    continue
                params = json.loads(rec.get("body_params") or "{}")
                if not isinstance(params, dict):
                    params = {}
                try:
                    result = await self.template_service.send_production_template(
                        tenant_id=tenant_id,
                        account_key=camp.get("account_key"),
                        template_name=camp["template_name"],
                        language=camp["template_language"],
                        to=rec["phone_e164"],
                        body_parameters=self._body_params_list(tpl.body_text, {k: str(v) for k, v in params.items()}),
                        charge_meta=False,
                    )
                    wamid = (result.message_id or "").strip()
                    if not wamid:
                        raise ValueError("Meta não retornou wamid")
                    await self.repository.update_recipient(
                        tenant_id,
                        int(rec["id"]),
                        {
                            "status": "sent",
                            "provider_message_id": wamid,
                            "sent_at": datetime.utcnow(),
                        },
                    )
                except Exception as exc:
                    await self.repository.update_recipient(
                        tenant_id,
                        int(rec["id"]),
                        {
                            "status": "failed",
                            "error_message": str(exc)[:500],
                            "failed_at": datetime.utcnow(),
                        },
                    )
                await self.repository.refresh_campaign_counters(tenant_id, int(camp["id"]))
                await asyncio.sleep(0.35)

    async def apply_provider_status(
        self,
        tenant_id: str,
        provider_message_id: str,
        status: str,
        *,
        error_code: str | None = None,
    ) -> dict[str, Any]:
        result = await asyncio.to_thread(
            self.repository.apply_provider_status_sync,
            tenant_id,
            provider_message_id,
            status,
            error_code=error_code,
        )
        return result

    async def get_campaign_detail(self, tenant_id: str, campaign_key: str) -> CampaignDetail:
        row = await self._require_campaign(tenant_id, campaign_key)
        recipients_raw = await self.repository.list_recipients(tenant_id=tenant_id, campaign_id=int(row["id"]))
        recipients: list[CampaignRecipientRow] = []
        for r in recipients_raw:
            body = r.get("body_params")
            if isinstance(body, str):
                try:
                    body = json.loads(body)
                except Exception:
                    body = {}
            if not isinstance(body, dict):
                body = {}
            recipients.append(
                CampaignRecipientRow(
                    row_number=int(r.get("row_number") or 0),
                    phone=str(r.get("phone_e164") or ""),
                    status=str(r.get("status") or "pending"),
                    body_params={str(k): str(v) for k, v in body.items()},
                    consent_ok=bool(r.get("consent_ok")),
                    error_message=r.get("error_message"),
                    sent_at=r.get("sent_at"),
                    delivered_at=r.get("delivered_at"),
                    read_at=r.get("read_at"),
                )
            )
        return CampaignDetail(campaign=self._to_summary(await self._with_acceptance(tenant_id, row)), recipients=recipients)

    async def build_results_xlsx(self, tenant_id: str, campaign_key: str) -> bytes:
        row = await self._require_campaign(tenant_id, campaign_key)
        recipients = await self.repository.list_recipients(tenant_id=tenant_id, campaign_id=int(row["id"]))
        extras = await self.repository.accepted_exception_counts(tenant_id)
        consumption = {}
        if self.meta_rate_engine is not None:
            consumption = estimate_actual_spend(
                rate_engine=self.meta_rate_engine,
                category=str(row.get("template_category") or "UTILITY"),
                delivered_count=int(row.get("delivered_count") or 0),
                read_count=int(row.get("read_count") or 0),
            )
        status_totals = presentation_counts(
            pending=int(row.get("pending_count") or 0),
            sent=int(row.get("sent_count") or 0),
            delivered=int(row.get("delivered_count") or 0),
            read=int(row.get("read_count") or 0),
            failed=int(row.get("failed_count") or 0),
            uncertain=int(row.get("uncertain_count") or 0),
            failed_accepted=int((extras.get(int(row["id"])) or {}).get("failed") or 0),
            uncertain_accepted=int((extras.get(int(row["id"])) or {}).get("uncertain") or 0),
        )
        return build_results_xlsx(
            campaign_name=row["name"],
            template_name=row["template_name"],
            category=str(row.get("template_category") or ""),
            status=str(row.get("status") or ""),
            recipients=recipients,
            consumption_estimate=consumption,
            status_totals=status_totals,
        )

    async def _update_consumption_estimate(self, tenant_id: str, campaign_id: int, camp_row: dict[str, Any]) -> None:
        if self.meta_rate_engine is None:
            return
        payload = estimate_actual_spend(
            rate_engine=self.meta_rate_engine,
            category=str(camp_row.get("template_category") or "UTILITY"),
            delivered_count=int(camp_row.get("delivered_count") or 0),
            read_count=int(camp_row.get("read_count") or 0),
        )
        await self.repository.update_campaign(
            tenant_id,
            campaign_id,
            {"meta_cost_estimate_json": payload},
        )

    async def _require_campaign(self, tenant_id: str, campaign_key: str) -> dict[str, Any]:
        row = await self.repository.get_campaign(tenant_id, campaign_key)
        if not row:
            raise ValueError("Campanha não encontrada")
        return row

    async def _with_acceptance(self, tenant_id: str, row: dict[str, Any]) -> dict[str, Any]:
        extras = await self.repository.accepted_exception_counts(tenant_id)
        item = dict(row)
        extra = extras.get(int(item["id"]), {"failed": 0, "uncertain": 0})
        item["failed_accepted"] = extra["failed"]
        item["uncertain_accepted"] = extra["uncertain"]
        return item

    @staticmethod
    def _to_summary(row: dict[str, Any]) -> CampaignSummary:
        estimate = row.get("meta_cost_estimate_json") or row.get("estimate_json")
        if isinstance(estimate, str):
            try:
                estimate = json.loads(estimate)
            except Exception:
                estimate = {}
        if not isinstance(estimate, dict):
            estimate = {}
        return CampaignSummary(
            id=str(row.get("campaign_key") or ""),
            name=str(row.get("name") or ""),
            status=str(row.get("status") or "draft"),
            account_key=row.get("account_key"),
            template_name=str(row.get("template_name") or ""),
            template_language=str(row.get("template_language") or ""),
            template_category=str(row.get("template_category") or ""),
            total_recipients=int(row.get("total_recipients") or 0),
            pending_count=int(row.get("pending_count") or 0),
            sent_count=int(row.get("sent_count") or 0),
            delivered_count=int(row.get("delivered_count") or 0),
            read_count=int(row.get("read_count") or 0),
            failed_count=int(row.get("failed_count") or 0),
            uncertain_count=int(row.get("uncertain_count") or 0),
            messages_sent=int(row.get("messages_sent") or 0)
            or (
                int(row.get("sent_count") or 0)
                + int(row.get("delivered_count") or 0)
                + int(row.get("read_count") or 0)
                + int(row.get("failed_accepted") or 0)
                + int(row.get("uncertain_accepted") or 0)
            ),
            meta_estimate=estimate,
            meta_disclaimer=META_BILLING_DISCLAIMER,
            created_at=row.get("created_at"),
            started_at=row.get("started_at"),
            completed_at=row.get("completed_at"),
        )