"""Session repository interfaces and implementations."""
from __future__ import annotations

import asyncio
import json
import time
from abc import ABC, abstractmethod
from datetime import datetime
from typing import Dict, Optional

from app.db.mysql import MySQLDatabase
from app.domain.session import ConversationSession, SessionMessage


class SessionRepository(ABC):
    """Interface for persisting conversation sessions."""

    @abstractmethod
    async def get_session(self, tenant_id: str, phone_number: str) -> Optional[ConversationSession]:
        raise NotImplementedError

    @abstractmethod
    async def save_session(self, session: ConversationSession) -> ConversationSession:
        raise NotImplementedError

    @abstractmethod
    async def delete_session(self, tenant_id: str, phone_number: str) -> None:
        raise NotImplementedError

    @abstractmethod
    async def list_sessions(self) -> list[ConversationSession]:
        raise NotImplementedError


class InMemorySessionRepository(SessionRepository):
    """Simple in-memory session repository with TTL support."""

    def __init__(self, ttl_seconds: int = 3600):
        self._ttl = ttl_seconds
        self._store: Dict[str, tuple[ConversationSession, float]] = {}
        self._lock = asyncio.Lock()

    def _key(self, tenant_id: str, phone_number: str) -> str:
        return f"{tenant_id}:{phone_number}"

    def _is_expired(self, stored_at: float) -> bool:
        if self._ttl <= 0:
            return False
        return time.time() - stored_at > self._ttl

    def _cleanup(self) -> None:
        now = time.time()
        expired_keys = [
            key for key, (_, stored_at) in self._store.items()
            if self._ttl > 0 and (now - stored_at) > self._ttl
        ]
        for key in expired_keys:
            self._store.pop(key, None)

    async def get_session(self, tenant_id: str, phone_number: str) -> Optional[ConversationSession]:
        async with self._lock:
            self._cleanup()
            key = self._key(tenant_id, phone_number)
            if key not in self._store:
                return None
            session, stored_at = self._store[key]
            if self._is_expired(stored_at):
                self._store.pop(key, None)
                return None
            return session

    async def save_session(self, session: ConversationSession) -> ConversationSession:
        async with self._lock:
            self._cleanup()
            session.touch()
            self._store[session.key] = (session, time.time())
            return session

    async def delete_session(self, tenant_id: str, phone_number: str) -> None:
        async with self._lock:
            key = self._key(tenant_id, phone_number)
            self._store.pop(key, None)

    async def list_sessions(self) -> list[ConversationSession]:
        async with self._lock:
            self._cleanup()
            sessions: list[ConversationSession] = []
            for session, stored_at in self._store.values():
                if not self._is_expired(stored_at):
                    sessions.append(session)
            return sessions


class MySQLSessionRepository(SessionRepository):
    """MySQL-backed session repository for durable state."""

    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def get_session(self, tenant_id: str, phone_number: str) -> Optional[ConversationSession]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _query() -> Optional[ConversationSession]:
            row = self.database.fetch_one(
                """
                SELECT session_id, phone_number, phone_number_id, display_phone_number,
                       active_flow, current_state, detected_intent,
                       conversation_history, session_state, context, last_flow,
                       last_interaction, updated_at
                FROM sessions
                WHERE tenant_id = %s AND phone_number = %s
                LIMIT 1
                """,
                (tenant_pk, phone_number),
            )
            return self._map_row(row, tenant_id) if row else None

        return await asyncio.to_thread(_query)

    async def save_session(self, session: ConversationSession) -> ConversationSession:
        tenant_pk = self.database.resolve_tenant_pk(session.tenant_id)

        def _save() -> ConversationSession:
            payload_history = json.dumps(
                [item.model_dump(mode="json") for item in session.conversation_history],
                ensure_ascii=False,
            )
            payload_state = json.dumps(session.conversation_state or {}, ensure_ascii=False)
            payload_context = json.dumps(session.context or {}, ensure_ascii=False)
            session.touch()
            self.database.execute(
                """
                INSERT INTO sessions (
                    session_id,
                    tenant_id,
                    phone_number,
                    phone_number_id,
                    display_phone_number,
                    active_flow,
                    current_state,
                    last_flow,
                    detected_intent,
                    conversation_history,
                    session_state,
                    context,
                    last_interaction,
                    updated_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    session_id = VALUES(session_id),
                    phone_number_id = VALUES(phone_number_id),
                    display_phone_number = VALUES(display_phone_number),
                    active_flow = VALUES(active_flow),
                    current_state = VALUES(current_state),
                    last_flow = VALUES(last_flow),
                    detected_intent = VALUES(detected_intent),
                    conversation_history = VALUES(conversation_history),
                    session_state = VALUES(session_state),
                    context = VALUES(context),
                    last_interaction = VALUES(last_interaction),
                    updated_at = VALUES(updated_at)
                """,
                (
                    session.session_id,
                    tenant_pk,
                    session.phone_number,
                    session.phone_number_id,
                    session.display_phone_number,
                    session.active_flow,
                    session.current_state,
                    session.last_flow,
                    session.detected_intent,
                    payload_history,
                    payload_state,
                    payload_context,
                    session.last_interaction,
                    session.updated_at,
                ),
            )
            return session

        return await asyncio.to_thread(_save)

    async def delete_session(self, tenant_id: str, phone_number: str) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        await asyncio.to_thread(
            self.database.execute,
            "DELETE FROM sessions WHERE tenant_id = %s AND phone_number = %s",
            (tenant_pk, phone_number),
        )

    async def list_sessions(self) -> list[ConversationSession]:
        def _list() -> list[ConversationSession]:
            rows = self.database.fetch_all(
                """
                SELECT s.session_id, s.phone_number, s.phone_number_id, s.display_phone_number,
                       s.active_flow, s.current_state, s.detected_intent,
                       s.conversation_history, s.session_state, s.context, s.last_flow,
                       s.last_interaction, s.updated_at,
                       t.external_key AS tenant_id
                FROM sessions s
                INNER JOIN tenants t ON t.id = s.tenant_id
                ORDER BY s.last_interaction DESC
                """
            )
            return [self._map_row(row, str(row["tenant_id"])) for row in rows]

        return await asyncio.to_thread(_list)

    def _map_row(self, row: dict, tenant_id: str) -> ConversationSession:
        raw_history = row.get("conversation_history") or []
        if isinstance(raw_history, str):
            try:
                raw_history = json.loads(raw_history)
            except json.JSONDecodeError:
                raw_history = []
        messages = [SessionMessage(**item) for item in raw_history if isinstance(item, dict)]

        raw_state = row.get("session_state") or {}
        if isinstance(raw_state, str):
            try:
                raw_state = json.loads(raw_state)
            except json.JSONDecodeError:
                raw_state = {}

        raw_context = row.get("context") or {}
        if isinstance(raw_context, str):
            try:
                raw_context = json.loads(raw_context)
            except json.JSONDecodeError:
                raw_context = {}

        return ConversationSession(
            session_id=str(row.get("session_id")),
            tenant_id=tenant_id,
            phone_number=str(row.get("phone_number") or ""),
            phone_number_id=row.get("phone_number_id"),
            display_phone_number=row.get("display_phone_number"),
            active_flow=row.get("active_flow"),
            current_state=row.get("current_state"),
            detected_intent=row.get("detected_intent"),
            conversation_history=messages,
            last_interaction=row.get("last_interaction") or datetime.utcnow(),
            conversation_state=raw_state,
            context=raw_context,
            last_flow=row.get("last_flow"),
            updated_at=row.get("updated_at") or datetime.utcnow(),
        )

