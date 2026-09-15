"""Service responsible for managing conversation sessions."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from app.domain.session import ConversationSession
from app.repositories.session_repository import SessionRepository
from app.utils.phone_utils import normalize_whatsapp_phone


class SessionService:
    """High-level session operations."""

    def __init__(self, repository: SessionRepository):
        self.repository = repository

    async def get_or_create_session(
        self,
        tenant_id: str,
        phone_number: str,
        *,
        phone_number_id: str | None = None,
        display_phone_number: str | None = None,
    ) -> ConversationSession:
        raw_phone = phone_number
        phone_number = normalize_whatsapp_phone(phone_number)

        session = await self.repository.get_session(tenant_id, phone_number)
        if not session and raw_phone != phone_number:
            legacy = await self.repository.get_session(tenant_id, raw_phone)
            if legacy:
                await self.repository.delete_session(tenant_id, raw_phone)
                legacy.phone_number = phone_number
                session = await self.repository.save_session(legacy)

        if session:
            changed = False
            if phone_number_id and session.phone_number_id != phone_number_id:
                session.phone_number_id = phone_number_id
                changed = True
            if display_phone_number and session.display_phone_number != display_phone_number:
                session.display_phone_number = display_phone_number
                changed = True
            if changed:
                session = await self.repository.save_session(session)
            return session

        session = ConversationSession(
            tenant_id=tenant_id,
            phone_number=phone_number,
            phone_number_id=phone_number_id,
            display_phone_number=display_phone_number,
            assignment_mode="ai",
            assigned_user_id=None,
            group_id=None,
        )
        session.context = {
            "assignment_mode": "ai",
            "group_name": "Geral",
        }
        return await self.repository.save_session(session)

    async def update_session(
        self,
        session: ConversationSession,
        state_updates: Optional[Dict[str, Any]] = None,
        context_updates: Optional[Dict[str, Any]] = None,
        last_flow: Optional[str] = None,
        active_flow: Optional[str] = None,
        current_state: Optional[str] = None,
        detected_intent: Optional[str] = None,
        phone_number_id: Optional[str] = None,
        display_phone_number: Optional[str] = None,
    ) -> ConversationSession:
        if state_updates:
            session.conversation_state.update(state_updates)
        if context_updates:
            session.context.update(context_updates)
        if last_flow:
            session.last_flow = last_flow
        if active_flow is not None:
            session.active_flow = active_flow
        if current_state is not None:
            session.current_state = current_state
        if detected_intent is not None:
            session.detected_intent = detected_intent
        if phone_number_id is not None:
            session.phone_number_id = phone_number_id
        if display_phone_number is not None:
            session.display_phone_number = display_phone_number
        session.last_interaction = datetime.utcnow()
        return await self.repository.save_session(session)

    async def clear_session(self, tenant_id: str, phone_number: str) -> None:
        await self.repository.delete_session(tenant_id, phone_number)

    async def list_sessions(self) -> list[ConversationSession]:
        return await self.repository.list_sessions()

