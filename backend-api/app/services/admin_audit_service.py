"""Administrative audit trail service."""
from __future__ import annotations

import asyncio
import json
from datetime import datetime
from typing import Any

from app.db.mysql import MySQLDatabase
from app.domain.admin_audit import AdminAuditEntry
from app.domain.auth import AuthenticatedUser


class AdminAuditService:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def append(
        self,
        *,
        tenant_id: str,
        action: str,
        entity_type: str,
        entity_key: str,
        summary: str,
        actor: AuthenticatedUser | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _insert() -> None:
            actor_fk = None
            if actor and actor.user_id:
                try:
                    actor_fk = int(actor.user_id)
                except ValueError:
                    actor_fk = None
            self.database.insert(
                """
                INSERT INTO admin_audit_logs (
                    tenant_id,
                    actor_user_id,
                    actor_email,
                    action,
                    entity_type,
                    entity_key,
                    summary,
                    metadata,
                    created_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    tenant_pk,
                    actor_fk,
                    actor.email if actor else None,
                    action,
                    entity_type,
                    entity_key,
                    summary,
                    json.dumps(metadata or {}, ensure_ascii=False),
                    datetime.utcnow(),
                ),
            )

        await asyncio.to_thread(_insert)

    async def list_by_tenant(self, tenant_id: str, limit: int = 100) -> list[AdminAuditEntry]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _list() -> list[AdminAuditEntry]:
            rows = self.database.fetch_all(
                """
                SELECT
                    aal.id,
                    aal.actor_user_id,
                    aal.actor_email,
                    aal.action,
                    aal.entity_type,
                    aal.entity_key,
                    aal.summary,
                    aal.metadata,
                    aal.created_at,
                    t.external_key AS tenant_id
                FROM admin_audit_logs aal
                INNER JOIN tenants t ON t.id = aal.tenant_id
                WHERE aal.tenant_id = %s
                ORDER BY aal.created_at DESC, aal.id DESC
                LIMIT %s
                """,
                (tenant_pk, limit),
            )
            items: list[AdminAuditEntry] = []
            for row in rows:
                metadata = row.get("metadata")
                if isinstance(metadata, str):
                    try:
                        metadata = json.loads(metadata)
                    except Exception:
                        metadata = {"raw": metadata}
                items.append(
                    AdminAuditEntry(
                        audit_id=str(row.get("id") or ""),
                        tenant_id=str(row.get("tenant_id") or tenant_id),
                        actor_user_id=str(row.get("actor_user_id")) if row.get("actor_user_id") is not None else None,
                        actor_email=str(row.get("actor_email") or "") or None,
                        action=str(row.get("action") or ""),
                        entity_type=str(row.get("entity_type") or ""),
                        entity_key=str(row.get("entity_key") or ""),
                        summary=str(row.get("summary") or ""),
                        metadata=metadata if isinstance(metadata, dict) else None,
                        created_at=row.get("created_at"),
                    )
                )
            return items

        return await asyncio.to_thread(_list)
