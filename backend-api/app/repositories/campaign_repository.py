from __future__ import annotations

import asyncio
import json
import uuid
from datetime import datetime, timedelta
from typing import Any

from app.db.mysql import MySQLDatabase
from app.services.campaign_status import should_promote


class CampaignRepository:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def create_campaign(self, *, tenant_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        key = payload.get("campaign_key") or str(uuid.uuid4())

        def _insert() -> dict[str, Any]:
            self.database.insert(
                """
                INSERT INTO whatsapp_campaigns (
                    tenant_id, campaign_key, name, status, account_key, phone_number_id,
                    template_name, template_language, template_category, body_variable_keys,
                    created_by_user_id, meta
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                (
                    tenant_pk,
                    key,
                    payload["name"],
                    payload.get("status", "draft"),
                    payload.get("account_key"),
                    payload.get("phone_number_id"),
                    payload["template_name"],
                    payload.get("template_language", "pt_BR"),
                    payload.get("template_category", "UTILITY"),
                    json.dumps(payload.get("body_variable_keys") or [], ensure_ascii=False),
                    payload.get("created_by_user_id"),
                    json.dumps(payload.get("meta") or {}, ensure_ascii=False),
                ),
            )
            return self.database.fetch_one(
                "SELECT * FROM whatsapp_campaigns WHERE tenant_id=%s AND campaign_key=%s",
                (tenant_pk, key),
            )

        return await asyncio.to_thread(_insert)

    async def list_campaigns(self, tenant_id: str, limit: int = 100) -> list[dict[str, Any]]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _list() -> list[dict[str, Any]]:
            return self.database.fetch_all(
                """
                SELECT * FROM whatsapp_campaigns
                WHERE tenant_id=%s
                ORDER BY updated_at DESC
                LIMIT %s
                """,
                (tenant_pk, limit),
            ) or []

        return await asyncio.to_thread(_list)

    async def get_campaign(self, tenant_id: str, campaign_key: str) -> dict[str, Any] | None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _get() -> dict[str, Any] | None:
            return self.database.fetch_one(
                "SELECT * FROM whatsapp_campaigns WHERE tenant_id=%s AND campaign_key=%s",
                (tenant_pk, campaign_key),
            )

        return await asyncio.to_thread(_get)

    async def update_campaign(self, tenant_id: str, campaign_id: int, fields: dict[str, Any]) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        allowed = {
            "status", "total_recipients", "sent_count", "delivered_count", "read_count",
            "pending_count", "failed_count", "uncertain_count", "estimate_json", "meta_cost_estimate_json",
            "confirmed_at", "started_at", "completed_at", "paused_at", "meta",
        }
        sets = []
        vals: list[Any] = []
        for k, v in fields.items():
            if k not in allowed:
                continue
            sets.append(f"{k}=%s")
            if k.endswith("_json") or k == "meta":
                vals.append(json.dumps(v, ensure_ascii=False) if isinstance(v, (dict, list)) else v)
            else:
                vals.append(v)
        if not sets:
            return

        def _run() -> None:
            self.database.execute(
                f"UPDATE whatsapp_campaigns SET {', '.join(sets)} WHERE tenant_id=%s AND id=%s",
                (*vals, tenant_pk, campaign_id),
            )

        await asyncio.to_thread(_run)

    async def replace_recipients(
        self, *, tenant_id: str, campaign_id: int, rows: list[dict[str, Any]]
    ) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _run() -> None:
            self.database.execute(
                "DELETE FROM whatsapp_campaign_recipients WHERE tenant_id=%s AND campaign_id=%s",
                (tenant_pk, campaign_id),
            )
            for row in rows:
                self.database.insert(
                    """
                    INSERT INTO whatsapp_campaign_recipients (
                        tenant_id, campaign_id, `row_number`, phone_e164, body_params,
                        consent_ok, status, idempotency_key, error_message
                    ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    """,
                    (
                        tenant_pk,
                        campaign_id,
                        row["row_number"],
                        row["phone"],
                        json.dumps(row.get("body_params") or {}, ensure_ascii=False),
                        1 if row.get("consent_ok") else 0,
                        "pending" if not row.get("errors") else "invalid",
                        row["idempotency_key"],
                        "; ".join(row.get("errors") or []) or None,
                    ),
                )

        await asyncio.to_thread(_run)

    async def list_pending_recipients(
        self, *, tenant_id: str, campaign_id: int, limit: int = 20
    ) -> list[dict[str, Any]]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _list() -> list[dict[str, Any]]:
            return self.database.fetch_all(
                """
                SELECT * FROM whatsapp_campaign_recipients
                WHERE tenant_id=%s AND campaign_id=%s AND status='pending'
                ORDER BY `row_number` ASC
                LIMIT %s
                """,
                (tenant_pk, campaign_id, limit),
            ) or []

        return await asyncio.to_thread(_list)

    async def update_recipient(self, tenant_id: str, recipient_id: int, fields: dict[str, Any]) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        sets = []
        vals: list[Any] = []
        for k, v in fields.items():
            sets.append(f"{k}=%s")
            if k == "body_params" and isinstance(v, dict):
                vals.append(json.dumps(v, ensure_ascii=False))
            else:
                vals.append(v)

        def _run() -> None:
            self.database.execute(
                f"UPDATE whatsapp_campaign_recipients SET {', '.join(sets)} WHERE tenant_id=%s AND id=%s",
                (*vals, tenant_pk, recipient_id),
            )

        await asyncio.to_thread(_run)

    async def running_campaigns(self, limit: int = 5) -> list[dict[str, Any]]:
        def _list() -> list[dict[str, Any]]:
            return self.database.fetch_all(
                """
                SELECT c.*, t.external_key AS tenant_external_key
                FROM whatsapp_campaigns c
                INNER JOIN tenants t ON t.id = c.tenant_id
                WHERE c.status='running'
                ORDER BY c.updated_at ASC
                LIMIT %s
                """,
                (limit,),
            ) or []

        return await asyncio.to_thread(_list)

    async def list_recipients(self, *, tenant_id: str, campaign_id: int) -> list[dict[str, Any]]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _list() -> list[dict[str, Any]]:
            return self.database.fetch_all(
                """
                SELECT * FROM whatsapp_campaign_recipients
                WHERE tenant_id=%s AND campaign_id=%s
                ORDER BY `row_number` ASC
                """,
                (tenant_pk, campaign_id),
            ) or []

        return await asyncio.to_thread(_list)

    async def accepted_exception_counts(self, tenant_id: str) -> dict[int, dict[str, int]]:
        """Falhas/incertas que a Meta chegou a aceitar (wamid, sent_at ou evento sent/delivered/read)."""
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _run() -> dict[int, dict[str, int]]:
            rows = self.database.fetch_all(
                """
                SELECT r.campaign_id, r.status, COUNT(*) AS total
                FROM whatsapp_campaign_recipients r
                WHERE r.tenant_id=%s
                  AND r.status IN ('failed', 'uncertain')
                  AND (
                    (r.provider_message_id IS NOT NULL AND r.provider_message_id <> '')
                    OR r.sent_at IS NOT NULL
                    OR EXISTS (
                      SELECT 1 FROM campaign_recipient_status_events e
                      WHERE e.recipient_id = r.id
                        AND e.status IN ('sent', 'delivered', 'read')
                    )
                  )
                GROUP BY r.campaign_id, r.status
                """,
                (tenant_pk,),
            ) or []
            out: dict[int, dict[str, int]] = {}
            for item in rows:
                bucket = out.setdefault(int(item["campaign_id"]), {"failed": 0, "uncertain": 0})
                status = str(item["status"])
                if status in bucket:
                    bucket[status] = int(item["total"] or 0)
            return out

        return await asyncio.to_thread(_run)

    async def reclaim_stale_sending(self, *, tenant_id: str, campaign_id: int, older_minutes: int = 15) -> int:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        cutoff = datetime.utcnow() - timedelta(minutes=max(5, older_minutes))

        def _run() -> int:
            now = datetime.utcnow()
            without_wamid = self.database.execute(
                """
                UPDATE whatsapp_campaign_recipients
                SET status='uncertain',
                    error_message='timeout_sem_wamid_possivel_aceite_meta',
                    finalized_at=%s
                WHERE tenant_id=%s AND campaign_id=%s AND status='sending'
                  AND updated_at < %s
                  AND (provider_message_id IS NULL OR provider_message_id='')
                """,
                (now, tenant_pk, campaign_id, cutoff),
            )
            with_wamid = self.database.execute(
                """
                UPDATE whatsapp_campaign_recipients
                SET status='sent', sent_at=COALESCE(sent_at, %s)
                WHERE tenant_id=%s AND campaign_id=%s AND status='sending'
                  AND updated_at < %s
                  AND provider_message_id IS NOT NULL AND provider_message_id <> ''
                """,
                (now, tenant_pk, campaign_id, cutoff),
            )
            return without_wamid + with_wamid

        return await asyncio.to_thread(_run)

    async def try_mark_sending(self, tenant_id: str, recipient_id: int) -> bool:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _run() -> bool:
            changed = self.database.execute(
                """
                UPDATE whatsapp_campaign_recipients
                SET status='sending'
                WHERE tenant_id=%s AND id=%s AND status='pending'
                """,
                (tenant_pk, recipient_id),
            )
            return changed > 0

        return await asyncio.to_thread(_run)

    async def refresh_campaign_counters(self, tenant_id: str, campaign_id: int) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _run() -> None:
            rows = self.database.fetch_all(
                """
                SELECT status, COUNT(*) AS total
                FROM whatsapp_campaign_recipients
                WHERE tenant_id=%s AND campaign_id=%s
                GROUP BY status
                """,
                (tenant_pk, campaign_id),
            ) or []
            counts = {str(r["status"]): int(r["total"] or 0) for r in rows}
            self.database.execute(
                """
                UPDATE whatsapp_campaigns
                SET pending_count=%s, sent_count=%s, delivered_count=%s, read_count=%s,
                    failed_count=%s, uncertain_count=%s
                WHERE tenant_id=%s AND id=%s
                """,
                (
                    counts.get("pending", 0) + counts.get("sending", 0),
                    counts.get("sent", 0),
                    counts.get("delivered", 0),
                    counts.get("read", 0),
                    counts.get("failed", 0) + counts.get("invalid", 0),
                    counts.get("uncertain", 0),
                    tenant_pk,
                    campaign_id,
                ),
            )

        await asyncio.to_thread(_run)

    def apply_provider_status_sync(
        self,
        tenant_key: str,
        provider_message_id: str,
        status: str,
        *,
        error_code: str | None = None,
    ) -> dict[str, Any]:
        wamid = (provider_message_id or "").strip()
        if not wamid:
            return {"ok": False, "reason": "missing_wamid"}
        incoming = (status or "").strip().lower()
        if incoming not in {"sent", "delivered", "read", "failed"}:
            return {"ok": False, "reason": "unsupported_status"}

        tenant_pk = self.database.resolve_tenant_pk(tenant_key)
        now = datetime.utcnow()
        with self.database.connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT r.* FROM whatsapp_campaign_recipients r
                    WHERE r.tenant_id=%s AND r.provider_message_id=%s
                    LIMIT 1 FOR UPDATE
                    """,
                    (tenant_pk, wamid),
                )
                recipient = cur.fetchone()
                if not recipient:
                    return {"ok": True, "applied": False, "reason": "not_campaign"}

                cur.execute(
                    """
                    INSERT IGNORE INTO campaign_recipient_status_events
                        (tenant_id, recipient_id, provider_message_id, status, error_code, applied)
                    VALUES (%s,%s,%s,%s,%s,0)
                    """,
                    (tenant_pk, recipient["id"], wamid, incoming, error_code),
                )
                cur.execute(
                    """
                    SELECT id FROM campaign_recipient_status_events
                    WHERE tenant_id=%s AND provider_message_id=%s AND status=%s
                    LIMIT 1
                    """,
                    (tenant_pk, wamid, incoming),
                )
                event = cur.fetchone()
                if not event:
                    return {"ok": True, "applied": False, "reason": "event_duplicate"}

                current = str(recipient.get("status") or "pending")
                if not should_promote(current, incoming):
                    cur.execute(
                        "UPDATE campaign_recipient_status_events SET applied=1 WHERE id=%s",
                        (event["id"],),
                    )
                    return {"ok": True, "applied": False, "reason": "no_promotion"}

                sets = ["status=%s"]
                vals: list[Any] = [incoming if incoming != "failed" else "failed"]
                if incoming == "delivered":
                    sets.append("delivered_at=COALESCE(delivered_at, %s)")
                    vals.append(now)
                elif incoming == "read":
                    sets.append("read_at=COALESCE(read_at, %s)")
                    vals.append(now)
                elif incoming == "failed":
                    sets.append("failed_at=COALESCE(failed_at, %s)")
                    vals.append(now)
                    if error_code:
                        sets.append("error_code=%s")
                        vals.append(error_code[:64])
                cur.execute(
                    f"UPDATE whatsapp_campaign_recipients SET {', '.join(sets)} WHERE tenant_id=%s AND id=%s",
                    (*vals, tenant_pk, recipient["id"]),
                )
                cur.execute(
                    "UPDATE campaign_recipient_status_events SET applied=1 WHERE id=%s",
                    (event["id"],),
                )

                campaign_id = int(recipient["campaign_id"])
                cur.execute(
                    """
                    SELECT status, COUNT(*) AS total
                    FROM whatsapp_campaign_recipients
                    WHERE tenant_id=%s AND campaign_id=%s
                    GROUP BY status
                    """,
                    (tenant_pk, campaign_id),
                )
                counts = {str(r["status"]): int(r["total"] or 0) for r in cur.fetchall() or []}
                cur.execute(
                    """
                    UPDATE whatsapp_campaigns
                    SET pending_count=%s, sent_count=%s, delivered_count=%s, read_count=%s,
                        failed_count=%s, uncertain_count=%s
                    WHERE tenant_id=%s AND id=%s
                    """,
                    (
                        counts.get("pending", 0) + counts.get("sending", 0),
                        counts.get("sent", 0),
                        counts.get("delivered", 0),
                        counts.get("read", 0),
                        counts.get("failed", 0) + counts.get("invalid", 0),
                        counts.get("uncertain", 0),
                        tenant_pk,
                        campaign_id,
                    ),
                )
        return {"ok": True, "applied": True, "status": incoming}