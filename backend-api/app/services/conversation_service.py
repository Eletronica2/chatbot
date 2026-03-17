"""Coordinates the orchestration between flows, AI and session state"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Dict

from app.domain.message import (
    ConversationAction,
    NormalizedMessage,
)
from app.services.ai_service import AIService
from app.services.flow_service import FlowService
from app.services.session_service import SessionService
from app.services.tenant_settings_service import TenantSettingsService

logger = logging.getLogger(__name__)


class ConversationService:
    """Central decision maker for every incoming WhatsApp message"""

    def __init__(
        self,
        session_service: SessionService,
        flow_service: FlowService,
        ai_service: AIService,
        tenant_settings_service: TenantSettingsService,
    ):
        self.session_service = session_service
        self.flow_service = flow_service
        self.ai_service = ai_service
        self.tenant_settings_service = tenant_settings_service

    async def handle_incoming_message(self, message: NormalizedMessage) -> ConversationAction:
        logger.info(
            "Handling message %s for tenant %s", message.message_id, message.tenant_id
        )
        session = await self.session_service.get_or_create_session(
            message.tenant_id, message.phone_number
        )
        self._append_message(session, role="user", content=message.content)

        flow_result = await self.flow_service.execute_flow(message, session)

        if flow_result.handled and flow_result.reply_text:
            logger.info(
                "Flow engine resolved message %s with reply", message.message_id
            )
            await self.session_service.update_session(
                session,
                state_updates=flow_result.session_state,
            )
            self._append_message(session, role="assistant", content=flow_result.reply_text)
            return ConversationAction(
                source="flow",
                reply_text=flow_result.reply_text,
                tenant_id=message.tenant_id,
                phone_number=message.phone_number,
                metadata=flow_result.metadata or {},
                session_state=session.conversation_state,
                requires_handoff=flow_result.requires_handoff,
            )

        logger.info("Flow unresolved, escalating to AI for message %s", message.message_id)
        tenant_settings = self.tenant_settings_service.get_or_create(message.tenant_id)
        if not tenant_settings.ai_enabled:
            logger.info(
                "AI disabled for tenant %s; returning deterministic fallback",
                message.tenant_id,
            )
            disabled_reply = (
                "No momento nao consigo continuar por IA. "
                "Posso transferir para atendimento humano."
            )
            self._append_message(session, role="assistant", content=disabled_reply)
            return ConversationAction(
                source="flow",
                reply_text=disabled_reply,
                tenant_id=message.tenant_id,
                phone_number=message.phone_number,
                metadata={"error": "ai_disabled"},
                session_state=session.conversation_state,
                requires_handoff=True,
            )

        ai_response = await self.ai_service.generate_response(
            message,
            session,
            metadata_overrides=tenant_settings.as_ai_metadata(),
        )
        await self.session_service.update_session(
            session,
            state_updates=ai_response.session_state,
        )
        self._append_message(session, role="assistant", content=ai_response.reply_text)
        return ConversationAction(
            source="ai",
            reply_text=ai_response.reply_text,
            tenant_id=message.tenant_id,
            phone_number=message.phone_number,
            metadata=ai_response.metadata or {},
            session_state=session.conversation_state,
        )

    def _append_message(self, session, role: str, content: str) -> None:
        if not content:
            return

        context: Dict[str, Any] = session.context or {}
        messages = context.get("messages")
        if not isinstance(messages, list):
            messages = []

        messages.append(
            {
                "id": str(len(messages) + 1),
                "role": role,
                "content": content,
                "created_at": datetime.utcnow().isoformat(),
            }
        )
        context["messages"] = messages[-50:]
        context["last_message"] = content
        context["last_role"] = role
        context["updated_at"] = datetime.utcnow().isoformat()
        session.context = context
