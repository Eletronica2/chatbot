"""Repositories for durable message storage."""
from __future__ import annotations

import asyncio
import json
from datetime import datetime
from typing import Any

from app.db.mysql import MySQLDatabase


class MessageRepository:
    async def was_processed(
        self,
        *,
        tenant_id: str,
        external_message_id: str | None,
        direction: str,
    ) -> bool:
        raise NotImplementedError

    async def append_message(
        self,
        *,
        tenant_id: str,
        session_id: str,
        direction: str,
        role: str,
        content: str,
        source: str,
        metadata: dict[str, Any] | None,
        external_message_id: str | None = None,
        phone_number_id: str | None = None,
    ) -> None:
        raise NotImplementedError

    async def list_messages(self, *, tenant_id: str, session_id: str, limit: int = 200) -> list[dict[str, Any]]:
        raise NotImplementedError

    async def get_message(
        self,
        *,
        tenant_id: str,
        session_id: str,
        message_id: int,
    ) -> dict[str, Any] | None:
        raise NotImplementedError

    async def count_incoming_since(self, *, tenant_id: str, since: datetime) -> int:
        raise NotImplementedError

    async def last_incoming_at(self, *, tenant_id: str, session_id: str) -> datetime | None:
        raise NotImplementedError

    async def patch_metadata_by_external_message_id(
        self,
        *,
        tenant_id: str,
        external_message_id: str,
        patch: dict[str, Any],
    ) -> None:
        raise NotImplementedError


class MySQLMessageRepository(MessageRepository):
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def was_processed(
        self,
        *,
        tenant_id: str,
        external_message_id: str | None,
        direction: str,
    ) -> bool:
        if not external_message_id:
            return False
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _query() -> bool:
            row = self.database.fetch_one(
                """
                SELECT m.id
                FROM messages m
                WHERE m.tenant_id = %s
                  AND m.external_message_id = %s
                  AND m.direction = %s
                LIMIT 1
                """,
                (tenant_pk, external_message_id, direction),
            )
            return row is not None

        return await asyncio.to_thread(_query)

    async def append_message(
        self,
        *,
        tenant_id: str,
        session_id: str,
        direction: str,
        role: str,
        content: str,
        source: str,
        metadata: dict[str, Any] | None,
        external_message_id: str | None = None,
        phone_number_id: str | None = None,
    ) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _insert() -> None:
            session_row = self.database.fetch_one(
                "SELECT id FROM sessions WHERE session_id = %s LIMIT 1",
                (session_id,),
            )
            if session_row is None:
                return
            payload = json.dumps(metadata or {}, ensure_ascii=False)
            self.database.insert(
                """
                INSERT INTO messages (
                    tenant_id,
                    session_id,
                    direction,
                    role,
                    content,
                    source,
                    metadata,
                    external_message_id,
                    phone_number_id
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    tenant_pk,
                    int(session_row["id"]),
                    direction,
                    role,
                    content,
                    source,
                    payload,
                    external_message_id,
                    phone_number_id,
                ),
            )

        await asyncio.to_thread(_insert)

    async def list_messages(self, *, tenant_id: str, session_id: str, limit: int = 200) -> list[dict[str, Any]]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _list() -> list[dict[str, Any]]:
            rows = self.database.fetch_all(
                """
                SELECT m.id, m.role, m.content, m.direction, m.source, m.metadata, m.created_at
                FROM messages m
                INNER JOIN sessions s ON s.id = m.session_id
                WHERE m.tenant_id = %s
                  AND s.session_id = %s
                ORDER BY m.created_at ASC
                LIMIT %s
                """,
                (tenant_pk, session_id, limit),
            )
            return rows

        return await asyncio.to_thread(_list)

    async def get_message(
        self,
        *,
        tenant_id: str,
        session_id: str,
        message_id: int,
    ) -> dict[str, Any] | None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _get() -> dict[str, Any] | None:
            return self.database.fetch_one(
                """
                SELECT m.id, m.role, m.content, m.metadata, m.phone_number_id
                FROM messages m
                INNER JOIN sessions s ON s.id = m.session_id
                WHERE m.tenant_id = %s
                  AND s.session_id = %s
                  AND m.id = %s
                LIMIT 1
                """,
                (tenant_pk, session_id, message_id),
            )

        return await asyncio.to_thread(_get)

    async def count_incoming_since(self, *, tenant_id: str, since: datetime) -> int:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _count() -> int:
            row = self.database.fetch_one(
                """
                SELECT COUNT(*) AS total
                FROM messages
                WHERE tenant_id = %s
                  AND direction = 'incoming'
                  AND created_at >= %s
                """,
                (tenant_pk, since),
            )
            return int((row or {}).get("total", 0) or 0)

        return await asyncio.to_thread(_count)

    async def last_incoming_at(self, *, tenant_id: str, session_id: str) -> datetime | None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _query() -> datetime | None:
            row = self.database.fetch_one(
                """
                SELECT m.created_at
                FROM messages m
                INNER JOIN sessions s ON s.id = m.session_id
                WHERE m.tenant_id = %s
                  AND s.session_id = %s
                  AND m.direction = 'incoming'
                ORDER BY m.created_at DESC
                LIMIT 1
                """,
                (tenant_pk, session_id),
            )
            if not row:
                return None
            value = row.get("created_at")
            return value if isinstance(value, datetime) else None

        return await asyncio.to_thread(_query)

    async def patch_metadata_by_external_message_id(
        self,
        *,
        tenant_id: str,
        external_message_id: str,
        patch: dict[str, Any],
    ) -> None:
        msg_id = (external_message_id or "").strip()
        if not msg_id:
            return
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        payload = json.dumps(patch or {}, ensure_ascii=False)

        def _patch() -> None:
            self.database.execute(
                """
                UPDATE messages
                SET metadata = JSON_MERGE_PATCH(COALESCE(metadata, '{}'), %s)
                WHERE tenant_id = %s
                  AND external_message_id = %s
                """,
                (payload, tenant_pk, msg_id),
            )

        await asyncio.to_thread(_patch)

