"""Coordinates orchestration between flow, AI, session and SaaS controls."""
from __future__ import annotations

import logging
import time
from datetime import datetime
from typing import Any, Dict

from app.domain.conversation_log import ConversationLog
from app.domain.message import ConversationAction, NormalizedMessage
from app.services.ai_service import AIService, IntentDetectionResult
from app.services.conversation_log_service import ConversationLogService
from app.services.flow_service import FlowService
from app.services.message_service import MessageService
from app.services.session_service import SessionService
from app.services.subscription_service import SubscriptionService
from app.services.tenant_settings_service import TenantSettingsService

logger = logging.getLogger(__name__)


class ConversationService:
    """Central decision maker for every incoming WhatsApp message."""

    def __init__(
        self,
        session_service: SessionService,
        flow_service: FlowService,
        ai_service: AIService,
        tenant_settings_service: TenantSettingsService,
        subscription_service: SubscriptionService,
        conversation_log_service: ConversationLogService,
        message_service: MessageService,
    ):
        self.session_service = session_service
        self.flow_service = flow_service
        self.ai_service = ai_service
        self.tenant_settings_service = tenant_settings_service
        self.subscription_service = subscription_service
        self.conversation_log_service = conversation_log_service
        self.message_service = message_service

    async def handle_incoming_message(self, message: NormalizedMessage) -> ConversationAction:
        started_at = time.perf_counter()
        logger.info("Handling message %s for tenant %s", message.message_id, message.tenant_id)

        if await self.message_service.was_processed(
            tenant_id=message.tenant_id,
            external_message_id=message.message_id,
            direction="incoming",
        ):
            logger.info("Skipping duplicated inbound message %s", message.message_id)
            return ConversationAction(
                source="duplicate",
                reply_text="",
                tenant_id=message.tenant_id,
                phone_number=message.phone_number,
                metadata={"duplicate": True},
                session_state={},
            )

        allowance = await self.subscription_service.check_message_allowance(message.tenant_id)
        if not allowance.allowed:
            blocked_reply = (
                "Seu plano esta temporariamente bloqueado. "
                "Atualize a assinatura para continuar usando o chatbot."
                if allowance.reason == "subscription_inactive"
                else "Seu limite mensal de mensagens foi atingido. "
                "Faça upgrade do plano para continuar atendendo automaticamente."
            )
            action = ConversationAction(
                source="subscription",
                reply_text=blocked_reply,
                tenant_id=message.tenant_id,
                phone_number=message.phone_number,
                metadata={
                    "error": allowance.reason,
                    "plan": allowance.subscription.plan,
                    "used_messages": allowance.used_messages,
                    "monthly_message_limit": allowance.subscription.monthly_message_limit,
                },
                session_state={},
            )
            await self._log_interaction(
                message=message,
                session_id=f"{message.tenant_id}:{message.phone_number}",
                flow_used=None,
                state=None,
                user_message=message.content,
                bot_response=blocked_reply,
                source="subscription",
                started_at=started_at,
                detected_intent=None,
            )
            return action

        session = await self.session_service.get_or_create_session(
            message.tenant_id,
            message.phone_number,
            phone_number_id=message.phone_number_id,
            display_phone_number=message.display_phone_number,
        )
        self._append_message(session, role="user", content=message.content)
        await self.message_service.append(
            tenant_id=message.tenant_id,
            session_id=session.session_id,
            direction="incoming",
            role="user",
            content=message.content,
            source="gateway",
            metadata=message.metadata or {},
            external_message_id=message.message_id,
            phone_number_id=message.phone_number_id,
        )

        intent_result = await self.ai_service.detect_intent(
            tenant_id=message.tenant_id,
            phone_number=message.phone_number,
            text=message.content,
            session_state=session.conversation_state,
        )
        enriched_message = self._with_detected_intent(message, intent_result)

        flow_result = await self.flow_service.execute_flow(enriched_message, session)

        if flow_result.handled and flow_result.reply_text:
            logger.info("Flow engine resolved message %s with reply", message.message_id)
            flow_metadata = flow_result.metadata or {}
            flow_name = str(flow_metadata.get("flow") or session.active_flow or "start")
            state_name = str(flow_metadata.get("state") or session.current_state or "greeting")

            persisted_intent = self._resolve_persisted_intent(
                intent_result=intent_result,
                fallback_intent=flow_result.detected_intent,
            )
            self._append_message(session, role="assistant", content=flow_result.reply_text)
            session = await self.session_service.update_session(
                session,
                state_updates=flow_result.session_state,
                active_flow=flow_name,
                current_state=state_name,
                detected_intent=persisted_intent,
                last_flow=flow_name,
                phone_number_id=message.phone_number_id,
                display_phone_number=message.display_phone_number,
            )
            await self.message_service.append(
                tenant_id=message.tenant_id,
                session_id=session.session_id,
                direction="outgoing",
                role="assistant",
                content=flow_result.reply_text,
                source="flow",
                metadata=flow_metadata,
                phone_number_id=message.phone_number_id,
            )

            response_metadata = dict(flow_metadata)
            if intent_result.intent:
                response_metadata["detected_intent"] = intent_result.intent
                response_metadata["confidence"] = intent_result.confidence

            action = ConversationAction(
                source="flow",
                reply_text=flow_result.reply_text,
                tenant_id=message.tenant_id,
                phone_number=message.phone_number,
                metadata=response_metadata,
                session_state=session.conversation_state,
                requires_handoff=flow_result.requires_handoff,
            )
            await self._log_interaction(
                message=message,
                session_id=session.session_id,
                flow_used=flow_name,
                state=state_name,
                user_message=message.content,
                bot_response=flow_result.reply_text,
                source="flow",
                started_at=started_at,
                detected_intent=persisted_intent,
            )
            return action

        logger.info("Flow unresolved, escalating to AI for message %s", message.message_id)
        tenant_settings = await self.tenant_settings_service.get_or_create(message.tenant_id)
        if not tenant_settings.ai_enabled:
            logger.info("AI disabled for tenant %s; returning deterministic fallback", message.tenant_id)
            disabled_reply = (
                "No momento nao consigo continuar por IA. "
                "Posso transferir para atendimento humano."
            )
            self._append_message(session, role="assistant", content=disabled_reply)
            session = await self.session_service.update_session(
                session,
                detected_intent=self._resolve_persisted_intent(intent_result=intent_result),
            )
            await self.message_service.append(
                tenant_id=message.tenant_id,
                session_id=session.session_id,
                direction="outgoing",
                role="assistant",
                content=disabled_reply,
                source="flow",
                metadata={"error": "ai_disabled"},
                phone_number_id=message.phone_number_id,
            )
            action = ConversationAction(
                source="flow",
                reply_text=disabled_reply,
                tenant_id=message.tenant_id,
                phone_number=message.phone_number,
                metadata={"error": "ai_disabled"},
                session_state=session.conversation_state,
                requires_handoff=True,
            )
            await self._log_interaction(
                message=message,
                session_id=session.session_id,
                flow_used=session.active_flow,
                state=session.current_state,
                user_message=message.content,
                bot_response=disabled_reply,
                source="flow",
                started_at=started_at,
                detected_intent=session.detected_intent,
            )
            return action

        ai_response = await self.ai_service.generate_response(
            enriched_message,
            session,
            metadata_overrides=tenant_settings.as_ai_metadata(),
        )
        detected_intent = ai_response.detected_intent or intent_result.intent
        confidence = ai_response.confidence if ai_response.confidence is not None else intent_result.confidence
        persist_intent = detected_intent if detected_intent and confidence > 0.7 else session.detected_intent

        self._append_message(session, role="assistant", content=ai_response.reply_text)
        session = await self.session_service.update_session(
            session,
            state_updates=ai_response.session_state,
            detected_intent=persist_intent,
            phone_number_id=message.phone_number_id,
            display_phone_number=message.display_phone_number,
        )
        await self.message_service.append(
            tenant_id=message.tenant_id,
            session_id=session.session_id,
            direction="outgoing",
            role="assistant",
            content=ai_response.reply_text,
            source="ai",
            metadata=ai_response.metadata,
            phone_number_id=message.phone_number_id,
        )

        metadata = dict(ai_response.metadata or {})
        if detected_intent:
            metadata["detected_intent"] = detected_intent
        if confidence is not None:
            metadata["confidence"] = confidence

        action = ConversationAction(
            source="ai",
            reply_text=ai_response.reply_text,
            tenant_id=message.tenant_id,
            phone_number=message.phone_number,
            metadata=metadata,
            session_state=session.conversation_state,
        )
        await self._log_interaction(
            message=message,
            session_id=session.session_id,
            flow_used=session.active_flow,
            state=session.current_state,
            user_message=message.content,
            bot_response=ai_response.reply_text,
            source="ai",
            started_at=started_at,
            detected_intent=persist_intent,
        )
        return action

    def _append_message(self, session, role: str, content: str) -> None:
        if not content:
            return

        session.append_history(role=role, content=content, limit=10)

        context: Dict[str, Any] = session.context or {}
        messages = [
            {
                "id": str(index),
                "role": item.role,
                "content": item.content,
                "created_at": item.created_at.isoformat(),
            }
            for index, item in enumerate(session.conversation_history, start=1)
        ]
        context["messages"] = messages[-50:]
        context["last_message"] = content
        context["last_role"] = role
        context["updated_at"] = datetime.utcnow().isoformat()
        session.context = context

    def _with_detected_intent(
        self,
        message: NormalizedMessage,
        intent_result: IntentDetectionResult,
    ) -> NormalizedMessage:
        metadata = dict(message.metadata or {})
        if intent_result.intent:
            metadata["detected_intent"] = intent_result.intent
            metadata["intent_confidence"] = intent_result.confidence
            metadata["intent_provider"] = intent_result.provider
        return message.model_copy(update={"metadata": metadata})

    def _resolve_persisted_intent(
        self,
        *,
        intent_result: IntentDetectionResult,
        fallback_intent: str | None = None,
    ) -> str | None:
        if intent_result.intent and intent_result.confidence > 0.7:
            return intent_result.intent
        if fallback_intent:
            return fallback_intent
        return None

    async def _log_interaction(
        self,
        *,
        message: NormalizedMessage,
        session_id: str,
        flow_used: str | None,
        state: str | None,
        user_message: str,
        bot_response: str,
        source: str,
        started_at: float,
        detected_intent: str | None,
    ) -> None:
        elapsed_ms = int((time.perf_counter() - started_at) * 1000)
        await self.conversation_log_service.append(
            ConversationLog(
                tenant_id=message.tenant_id,
                phone_number=message.phone_number,
                session_id=session_id,
                user_message=user_message,
                bot_response=bot_response,
                flow_used=flow_used,
                state=state,
                source=source,
                detected_intent=detected_intent,
                response_time_ms=elapsed_ms,
            )
        )

