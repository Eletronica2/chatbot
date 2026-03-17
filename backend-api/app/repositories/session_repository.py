"""Session repository interfaces and in-memory implementation"""
from __future__ import annotations

import asyncio
import time
from abc import ABC, abstractmethod
from typing import Dict, Optional

from app.domain.session import ConversationSession


class SessionRepository(ABC):
    """Interface for persisting conversation sessions"""

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
    """Simple in-memory session repository with TTL support"""

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
