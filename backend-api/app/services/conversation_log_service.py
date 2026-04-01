"""Persistent conversation log service for observability."""
from __future__ import annotations

import asyncio
from typing import List

from app.db.mysql import MySQLDatabase
from app.domain.conversation_log import ConversationLog


class ConversationLogService:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def append(self, item: ConversationLog) -> None:
        tenant_pk = self.database.resolve_tenant_pk(item.tenant_id)

        def _insert() -> None:
            session_row = self.database.fetch_one(
                "SELECT id FROM sessions WHERE session_id = %s LIMIT 1",
                (item.session_id,),
            )
            session_fk = int(session_row["id"]) if session_row else None
            self.database.insert(
                """
                INSERT INTO conversation_logs (
                    tenant_id,
                    session_id,
                    phone_number,
                    user_message,
                    bot_response,
                    flow_used,
                    state,
                    source,
                    detected_intent,
                    response_time_ms,
                    created_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    tenant_pk,
                    session_fk,
                    item.phone_number,
                    item.user_message,
                    item.bot_response,
                    item.flow_used,
                    item.state,
                    item.source,
                    item.detected_intent,
                    item.response_time_ms,
                    item.created_at,
                ),
            )

        await asyncio.to_thread(_insert)

    async def list_by_tenant(self, tenant_id: str, limit: int = 200) -> List[ConversationLog]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _list() -> List[ConversationLog]:
            rows = self.database.fetch_all(
                """
                SELECT phone_number, user_message, bot_response, flow_used, state,
                       source, detected_intent, response_time_ms, created_at,
                       COALESCE(s.session_id, '') AS session_id
                FROM conversation_logs cl
                LEFT JOIN sessions s ON s.id = cl.session_id
                WHERE cl.tenant_id = %s
                ORDER BY cl.created_at DESC
                LIMIT %s
                """,
                (tenant_pk, limit),
            )
            return [
                ConversationLog(
                    tenant_id=tenant_id,
                    phone_number=str(row.get("phone_number") or ""),
                    session_id=str(row.get("session_id") or ""),
                    user_message=str(row.get("user_message") or ""),
                    bot_response=str(row.get("bot_response") or ""),
                    flow_used=row.get("flow_used"),
                    state=row.get("state"),
                    source=str(row.get("source") or "flow"),
                    detected_intent=row.get("detected_intent"),
                    response_time_ms=int(row.get("response_time_ms") or 0),
                    created_at=row.get("created_at"),
                )
                for row in rows
            ]

        return await asyncio.to_thread(_list)

