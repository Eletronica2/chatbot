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

    async def count_incoming_since(self, *, tenant_id: str, since: datetime) -> int:
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
                SELECT m.id, m.role, m.content, m.direction, m.source, m.created_at
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

