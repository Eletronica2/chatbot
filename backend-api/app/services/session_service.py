"""Service responsible for managing conversation sessions"""
from __future__ import annotations

from typing import Any, Dict, Optional

from app.domain.session import ConversationSession
from app.repositories.session_repository import SessionRepository


class SessionService:
    """High-level session operations"""

    def __init__(self, repository: SessionRepository):
        self.repository = repository

    async def get_or_create_session(self, tenant_id: str, phone_number: str) -> ConversationSession:
        session = await self.repository.get_session(tenant_id, phone_number)
        if session:
            return session

        session = ConversationSession(
            tenant_id=tenant_id,
            phone_number=phone_number,
        )
        return await self.repository.save_session(session)

    async def update_session(
        self,
        session: ConversationSession,
        state_updates: Optional[Dict[str, Any]] = None,
        context_updates: Optional[Dict[str, Any]] = None,
        last_flow: Optional[str] = None,
    ) -> ConversationSession:
        if state_updates:
            session.conversation_state.update(state_updates)
        if context_updates:
            session.context.update(context_updates)
        if last_flow:
            session.last_flow = last_flow
        return await self.repository.save_session(session)

    async def clear_session(self, tenant_id: str, phone_number: str) -> None:
        await self.repository.delete_session(tenant_id, phone_number)

    async def list_sessions(self) -> list[ConversationSession]:
        return await self.repository.list_sessions()
