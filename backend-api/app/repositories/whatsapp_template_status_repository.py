"""MySQL persistence for WhatsApp template status cache."""
from __future__ import annotations

import asyncio
from datetime import datetime
from typing import Any

from app.db.mysql import MySQLDatabase
from app.services.template_status_logic import effective_status, normalize_status, should_apply_webhook


class WhatsAppTemplateStatusRepository:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def try_record_dedupe(self, *, tenant_pk: int, dedupe_key: str) -> bool:
        def _write() -> bool:
            with self.database.transaction() as conn:
                with conn.cursor() as cursor:
                    cursor.execute(
                        """
                        INSERT INTO whatsapp_template_webhook_dedup (dedupe_key, tenant_id)
                        VALUES (%s, %s)
                        """,
                        (dedupe_key, tenant_pk),
                    )
                    return cursor.rowcount == 1

        try:
            return await asyncio.to_thread(_write)
        except Exception as exc:
            if "Duplicate" in str(exc):
                return False
            raise

    async def apply_webhook(
        self,
        *,
        tenant_id: str,
        account_key: str,
        template_id: str | None,
        template_name: str,
        language: str,
        status: str,
        rejected_reason: str | None,
        event_time: int,
        dedupe_key: str,
    ) -> dict[str, Any]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        if not await self.try_record_dedupe(tenant_pk=tenant_pk, dedupe_key=dedupe_key):
            return {"applied": False, "reason": "duplicate"}

        name = template_name.strip()
        lang = language.strip() or "pt_BR"
        incoming = normalize_status(status)

        def _write() -> dict[str, Any]:
            row = self.database.fetch_one(
                """
                SELECT graph_status, webhook_status, graph_synced_at, webhook_event_at
                FROM whatsapp_template_status
                WHERE tenant_id = %s AND account_key = %s AND template_name = %s AND language = %s
                LIMIT 1
                """,
                (tenant_pk, account_key, name, lang),
            )
            stored_effective = None
            stored_webhook_at = None
            if row:
                stored_webhook_at = row.get("webhook_event_at")
                stored_effective = effective_status(
                    graph_status=row.get("graph_status"),
                    webhook_status=row.get("webhook_status"),
                    graph_synced_at=row.get("graph_synced_at"),
                    webhook_event_at=row.get("webhook_event_at"),
                )
            apply, skip = should_apply_webhook(
                stored_webhook_event_at=stored_webhook_at,
                event_time=event_time,
                stored_effective=stored_effective,
                new_status=incoming,
            )
            if not apply:
                return {"applied": False, "reason": skip or "skipped"}
            with self.database.transaction() as conn:
                with conn.cursor() as cursor:
                    cursor.execute(
                        """
                        INSERT INTO whatsapp_template_status (
                            tenant_id, account_key, template_id, template_name, language,
                            webhook_status, rejected_reason, webhook_event_at
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                        ON DUPLICATE KEY UPDATE
                            template_id = COALESCE(VALUES(template_id), template_id),
                            webhook_status = VALUES(webhook_status),
                            rejected_reason = COALESCE(VALUES(rejected_reason), rejected_reason),
                            webhook_event_at = VALUES(webhook_event_at),
                            updated_at = CURRENT_TIMESTAMP
                        """,
                        (
                            tenant_pk,
                            account_key,
                            template_id,
                            name,
                            lang,
                            incoming,
                            (rejected_reason or None),
                            event_time,
                        ),
                    )
            return {"applied": True, "status": incoming}

        return await asyncio.to_thread(_write)

    async def sync_from_graph_rows(
        self,
        *,
        tenant_id: str,
        account_key: str,
        rows: list[dict[str, Any]],
    ) -> None:
        if not rows:
            return
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        now_unix = int(datetime.utcnow().timestamp())

        def _write() -> None:
            with self.database.transaction() as conn:
                with conn.cursor() as cursor:
                    for row in rows:
                        name = str(row.get("name") or "").strip()
                        if not name:
                            continue
                        lang = str(row.get("language") or "pt_BR").strip()
                        status = normalize_status(str(row.get("status") or "PENDING"))
                        template_id = str(row.get("template_id") or row.get("id") or "").strip() or None
                        reason = row.get("rejected_reason")
                        if reason is not None:
                            reason = str(reason).strip() or None
                        cursor.execute(
                            """
                            INSERT INTO whatsapp_template_status (
                                tenant_id, account_key, template_id, template_name, language,
                                graph_status, graph_synced_at, rejected_reason
                            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                            ON DUPLICATE KEY UPDATE
                                template_id = COALESCE(VALUES(template_id), template_id),
                                graph_status = VALUES(graph_status),
                                graph_synced_at = VALUES(graph_synced_at),
                                rejected_reason = COALESCE(VALUES(rejected_reason), rejected_reason),
                                updated_at = CURRENT_TIMESTAMP
                            """,
                            (
                                tenant_pk,
                                account_key,
                                template_id,
                                name,
                                lang,
                                status,
                                now_unix,
                                reason,
                            ),
                        )

        await asyncio.to_thread(_write)

    async def list_watch(
        self,
        *,
        tenant_id: str,
        account_key: str,
        since_unix: int,
    ) -> list[dict[str, Any]]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _query() -> list[dict[str, Any]]:
            rows = self.database.fetch_all(
                """
                SELECT
                    template_id,
                    template_name,
                    language,
                    graph_status,
                    webhook_status,
                    rejected_reason,
                    graph_synced_at,
                    webhook_event_at,
                    UNIX_TIMESTAMP(updated_at) AS updated_at_unix
                FROM whatsapp_template_status
                WHERE tenant_id = %s
                  AND account_key = %s
                  AND UNIX_TIMESTAMP(updated_at) > %s
                ORDER BY updated_at ASC
                """,
                (tenant_pk, account_key, since_unix),
            )
            out: list[dict[str, Any]] = []
            for row in rows:
                eff = effective_status(
                    graph_status=row.get("graph_status"),
                    webhook_status=row.get("webhook_status"),
                    graph_synced_at=row.get("graph_synced_at"),
                    webhook_event_at=row.get("webhook_event_at"),
                )
                reason = row.get("rejected_reason")
                if reason in (None, "", "NONE"):
                    reason = None
                out.append(
                    {
                        "template_id": row.get("template_id"),
                        "name": row.get("template_name"),
                        "language": row.get("language"),
                        "status": eff,
                        "rejected_reason": reason,
                        "updated_at": int(row.get("updated_at_unix") or 0),
                    }
                )
            return out

        return await asyncio.to_thread(_query)