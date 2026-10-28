"""Coordinates orchestration between flow, AI, session and SaaS controls."""
from __future__ import annotations

import asyncio
import logging
import re
import time
from datetime import datetime
from typing import Any, Dict

from app.domain.conversation_log import ConversationLog
from app.domain.outbound_coalescer import coalesce_text_parts
from app.domain.execution_context import ExecutionContext
from app.domain.message import ConversationAction, NormalizedMessage
from app.domain.session import ConversationSession
from app.services.ai_service import AIService, IntentDetectionResult
from app.services.conversation_log_service import ConversationLogService
from app.services.flow_service import FlowService
from app.services.message_service import MessageService
from app.services.order_assistant import START_ACTION as START_ORDER_ACTION
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
        billing_gate: Any | None = None,
        ai_usage_service: Any | None = None,
        order_assistant: Any | None = None,
    ):
        self.session_service = session_service
        self.flow_service = flow_service
        self.ai_service = ai_service
        self.tenant_settings_service = tenant_settings_service
        self.subscription_service = subscription_service
        self.conversation_log_service = conversation_log_service
        self.message_service = message_service
        self.billing_gate = billing_gate
        self.ai_usage_service = ai_usage_service
        self.order_assistant = order_assistant

    def _billing_v2_active(self) -> bool:
        return self.billing_gate is not None and bool(self.billing_gate.enabled)

    async def handle_incoming_message(
        self,
        message: NormalizedMessage,
        *,
        execution_context: ExecutionContext | None = None,
    ) -> ConversationAction:
        """Inbound never consumes. The single reply of the turn is reserved before send."""
        ctx = execution_context or ExecutionContext.production()
        if ctx.persist and not ctx.is_test:
            tenant_settings = await self.tenant_settings_service.get_or_create(message.tenant_id)
            block_reason = tenant_settings.auto_reply_block_reason(message.phone_number)
            if block_reason:
                if await self.message_service.was_processed(
                    tenant_id=message.tenant_id,
                    external_message_id=message.message_id,
                    direction="incoming",
                ):
                    return ConversationAction(
                        source="duplicate",
                        reply_text="",
                        tenant_id=message.tenant_id,
                        phone_number=message.phone_number,
                        metadata={"duplicate": True},
                        session_state={},
                    )
                return await self._auto_reply_blocked(message, ctx, block_reason, tenant_settings.auto_reply_mode)
        if not self._billing_v2_active():
            return await self._handle_incoming_core(message, execution_context=ctx)

        enforce = ctx.allow_billing and ctx.persist and not ctx.is_test
        if enforce:
            try:
                decision = await asyncio.to_thread(
                    self.billing_gate.preflight, message.tenant_id, category="SERVICE"
                )
            except Exception:
                logger.exception("billing_preflight_failed tenant=%s", message.tenant_id)
                decision = None
            if decision is None or not decision.allowed:
                if await self.message_service.was_processed(
                    tenant_id=message.tenant_id,
                    external_message_id=message.message_id,
                    direction="incoming",
                ):
                    return ConversationAction(
                        source="duplicate",
                        reply_text="",
                        tenant_id=message.tenant_id,
                        phone_number=message.phone_number,
                        metadata={"duplicate": True},
                        session_state={},
                    )
                return await self._billing_blocked(message, ctx, decision)

        action = await self._handle_incoming_core(message, execution_context=ctx)
        metadata = dict(action.metadata or {})
        if not action.reply_text:
            return action
        if not enforce:
            metadata["billing"] = {"enforced": False, "dry_run": True}
            return action.model_copy(update={"metadata": metadata})

        parts = coalesce_text_parts([action.reply_text])
        try:
            reservation = await asyncio.to_thread(
                self.billing_gate.reserve,
                message.tenant_id,
                category="SERVICE",
                category_source="freeform_service_reply",
                source_path=self._billing_source_path(action.source),
                idempotency_key=f"reply:{message.message_id}",
                phone_number_id=message.phone_number_id,
            )
        except Exception:
            logger.exception("billing_reserve_failed tenant=%s message=%s", message.tenant_id, message.message_id)
            reservation = None
        if reservation is None or not reservation.allowed:
            metadata["billing"] = {
                "enforced": True,
                "blocked": True,
                "code": reservation.code if reservation else "billing_error",
            }
            return action.model_copy(update={"reply_text": "", "metadata": metadata, "requires_handoff": True})
        metadata["billing"] = {
            "enforced": True,
            "reservation_id": reservation.reservation_id,
            "billing_mode": reservation.billing_mode,
            "level": reservation.level,
            "parts_before": parts.parts_before,
            "parts_after": parts.parts_after,
        }
        return action.model_copy(update={"metadata": metadata})

    @staticmethod
    def _billing_source_path(source: str) -> str:
        if source.startswith("ai"):
            return "ai"
        if source == "flow":
            return "flow"
        return "system"

    async def _billing_blocked(self, message: NormalizedMessage, ctx: ExecutionContext, decision: Any) -> ConversationAction:
        code = getattr(decision, "code", None) or "billing_error"
        session = await self._resolve_session(message, ctx)
        self._append_message(session, role="user", content=message.content)
        await self._persist_message(
            ctx,
            tenant_id=message.tenant_id,
            session_id=session.session_id,
            direction="incoming",
            role="user",
            content=message.content,
            source="gateway",
            metadata={**(message.metadata or {}), "billing_blocked": code},
            external_message_id=message.message_id,
            phone_number_id=message.phone_number_id,
        )
        context = dict(session.context or {})
        context["human_handoff_pending"] = True
        context["human_handoff_reason"] = code
        context["human_handoff_at"] = datetime.utcnow().isoformat()
        context["unread_count"] = int(context.get("unread_count", 0) or 0) + 1
        session = await self._persist_session_update(ctx, session, context_updates=context)
        return ConversationAction(
            source="billing_blocked",
            reply_text="",
            tenant_id=message.tenant_id,
            phone_number=message.phone_number,
            metadata={"billing": {"enforced": True, "blocked": True, "code": code}, "human_handoff_pending": True},
            session_state=session.conversation_state,
            requires_handoff=True,
        )

    async def _auto_reply_blocked(
        self, message: NormalizedMessage, ctx: ExecutionContext, reason: str, mode: str
    ) -> ConversationAction:
        """Store the inbound and leave it for a human; no flow, no AI, no billing reservation, nothing sent."""
        logger.info("auto_reply_blocked tenant=%s message=%s reason=%s", message.tenant_id, message.message_id, reason)
        session = await self._resolve_session(message, ctx)
        self._append_message(session, role="user", content=message.content)
        await self._persist_message(
            ctx,
            tenant_id=message.tenant_id,
            session_id=session.session_id,
            direction="incoming",
            role="user",
            content=message.content,
            source="gateway",
            metadata={**(message.metadata or {}), "auto_reply_blocked": reason},
            external_message_id=message.message_id,
            phone_number_id=message.phone_number_id,
        )
        context = dict(session.context or {})
        context["human_handoff_pending"] = True
        context["human_handoff_reason"] = reason
        context["human_handoff_at"] = datetime.utcnow().isoformat()
        context["unread_count"] = int(context.get("unread_count", 0) or 0) + 1
        context["last_message"] = message.content
        session = await self._persist_session_update(ctx, session, context_updates=context)
        return ConversationAction(
            source="auto_reply_disabled",
            reply_text="",
            tenant_id=message.tenant_id,
            phone_number=message.phone_number,
            metadata={"auto_reply": {"mode": mode, "blocked": True, "reason": reason}, "human_handoff_pending": True},
            session_state=session.conversation_state,
            requires_handoff=True,
        )

    async def _record_ai_usage(self, message: NormalizedMessage, session: ConversationSession, metadata: Dict[str, Any] | None, ctx: ExecutionContext) -> None:
        if self.ai_usage_service is None or not ctx.persist:
            return
        await self.ai_usage_service.record(
            message.tenant_id,
            metadata,
            session_id=getattr(session, "session_id", None),
            inbound_message_id=message.message_id,
        )

    async def _handle_incoming_core(
        self,
        message: NormalizedMessage,
        *,
        execution_context: ExecutionContext | None = None,
    ) -> ConversationAction:
        started_at = time.perf_counter()
        ctx = execution_context or ExecutionContext.production()
        logger.info(
            "Handling message %s for tenant %s (mode=%s)",
            message.message_id,
            message.tenant_id,
            ctx.mode.value,
        )

        if ctx.persist and await self.message_service.was_processed(
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

        if ctx.allow_billing and not self._billing_v2_active():
            allowance = await self.subscription_service.check_message_allowance(message.tenant_id)
            if not allowance.allowed:
                handoff_reply = (
                    "Aguarde um momento — já vamos te responder! 🙋\n"
                    "Um atendente da casa vai continuar essa conversa com você."
                )
                session = await self._resolve_session(message, ctx)
                self._append_message(session, role="user", content=message.content)
                await self._persist_message(
                    ctx,
                    tenant_id=message.tenant_id,
                    session_id=session.session_id,
                    direction="incoming",
                    role="user",
                    content=message.content,
                    source="gateway",
                    metadata={
                        **(message.metadata or {}),
                        "handoff_reason": allowance.reason,
                    },
                    external_message_id=message.message_id,
                    phone_number_id=message.phone_number_id,
                )
                context = dict(session.context or {})
                context["human_handoff_pending"] = True
                context["human_handoff_reason"] = allowance.reason
                context["human_handoff_at"] = datetime.utcnow().isoformat()
                context["unread_count"] = int(context.get("unread_count", 0) or 0) + 1
                session = await self._persist_session_update(
                    ctx,
                    session,
                    context_updates=context,
                )
                handoff_metadata = {
                    "error": allowance.reason,
                    "human_handoff_pending": True,
                    "plan": allowance.subscription.plan,
                    "used_messages": allowance.used_messages,
                    "monthly_message_limit": allowance.subscription.monthly_message_limit,
                }
                if ctx.is_test:
                    handoff_metadata["dry_run"] = True
                action = ConversationAction(
                    source="subscription_handoff",
                    reply_text=handoff_reply,
                    tenant_id=message.tenant_id,
                    phone_number=message.phone_number,
                    metadata=handoff_metadata,
                    session_state=session.conversation_state,
                    requires_handoff=True,
                )
                await self._log_interaction(
                    message=message,
                    session_id=session.session_id,
                    flow_used=None,
                    state=None,
                    user_message=message.content,
                    bot_response=handoff_reply,
                    source="subscription_handoff",
                    started_at=started_at,
                    detected_intent=None,
                    execution_context=ctx,
                )
                return action

        session = await self._resolve_session(message, ctx)
        if ctx.persist:
            session = await self._ensure_operational_defaults(session)

        # Human ownership: persist inbound, do NOT auto-reply.
        if ctx.persist and self._is_human_owned(session):
            self._append_message(session, role="user", content=message.content)
            await self._persist_message(
                ctx,
                tenant_id=message.tenant_id,
                session_id=session.session_id,
                direction="incoming",
                role="user",
                content=message.content,
                source="gateway",
                metadata={**(message.metadata or {}), "awaiting_human": True},
                external_message_id=message.message_id,
                phone_number_id=message.phone_number_id,
            )
            context = dict(session.context or {})
            context["unread_count"] = int(context.get("unread_count", 0) or 0) + 1
            context["last_message"] = message.content
            context["updated_at"] = datetime.utcnow().isoformat()
            session = await self._persist_session_update(ctx, session, context_updates=context)
            return ConversationAction(
                source="human_owned",
                reply_text="",
                tenant_id=message.tenant_id,
                phone_number=message.phone_number,
                metadata={
                    "assignment_mode": "human",
                    "assigned_user_id": session.assigned_user_id,
                    "suppressed_auto_reply": True,
                },
                session_state=session.conversation_state,
                requires_handoff=True,
            )

        self._append_message(session, role="user", content=message.content)
        await self._persist_message(
            ctx,
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

        order_action = await self._maybe_order_assistant(message, session, ctx, started_at)
        if order_action is not None:
            return order_action

        intent_result = await self.ai_service.detect_intent(
            tenant_id=message.tenant_id,
            phone_number=message.phone_number,
            text=message.content,
            session_state=session.conversation_state,
        )
        enriched_message = self._with_detected_intent(message, intent_result)

        flow_result = await self.flow_service.execute_flow(enriched_message, session)

        # --- Case 1: Flow wants AI to complete the response (fallback_ai) ---
        if flow_result.requires_ai_fallback:
            logger.info(
                "Flow engine signaled requires_ai_fallback for message %s",
                message.message_id,
            )
            tenant_settings = await self.tenant_settings_service.get_or_create(message.tenant_id)
            if tenant_settings.ai_enabled:
                # Pass flow context to AI so it can respond naturally
                flow_metadata = flow_result.metadata or {}
                ai_metadata = dict(message.metadata or {})
                ai_metadata.update({
                    "flow_state_message": flow_metadata.get("flow_state_message"),
                    "options": flow_metadata.get("options"),
                    "collected_data": flow_result.collected_data,
                    "resolution_reason": "fallback_ai",
                })
                enriched_message_for_ai = enriched_message.model_copy(
                    update={"metadata": ai_metadata}
                )
                ai_response = await self.ai_service.generate_response(
                    enriched_message_for_ai,
                    session,
                    metadata_overrides=tenant_settings.as_ai_metadata(),
                )
                await self._record_ai_usage(message, session, ai_response.metadata, ctx)
                if not ai_response.handled:
                    return await self._ai_unavailable_handoff(
                        message, session, ai_response.metadata, ctx, source="ai_fallback", started_at=started_at
                    )
                if ai_response.handled and ai_response.reply_text:
                    if await self._should_suppress_auto_reply(message, ctx):
                        return self._suppressed_late_reply(message, session, source="ai_fallback")
                    flow_state_message = flow_metadata.get("flow_state_message")
                    reply = self._compose_ai_fallback_reply(
                        ai_response.reply_text,
                        flow_state_message if isinstance(flow_state_message, str) else None,
                    )
                    source = "ai_fallback"
                    combined_metadata = dict(flow_metadata)
                    combined_metadata.update(ai_metadata)
                    combined_metadata["source"] = source
                    if intent_result.intent:
                        combined_metadata["detected_intent"] = intent_result.intent
                    persisted_intent = self._resolve_persisted_intent(
                        intent_result=intent_result,
                        fallback_intent=flow_result.detected_intent,
                    )
                    flow_name = self._resolve_flow_name(flow_metadata, session)
                    state_name = str(flow_metadata.get("state") or session.current_state or "greeting")
                    self._append_message(session, role="assistant", content=reply)
                    self._clear_transient_ai_handoff(session)
                    session = await self._persist_session_update(
                        ctx,
                        session,
                        state_updates=flow_result.session_state,
                        active_flow=flow_name,
                        current_state=state_name,
                        detected_intent=persisted_intent,
                        last_flow=flow_name,
                        phone_number_id=message.phone_number_id,
                        display_phone_number=message.display_phone_number,
                    )
                    if ctx.is_test:
                        combined_metadata["dry_run"] = True
                    await self._persist_message(
                        ctx,
                        tenant_id=message.tenant_id,
                        session_id=session.session_id,
                        direction="outgoing",
                        role="assistant",
                        content=reply,
                        source=source,
                        metadata=combined_metadata,
                        phone_number_id=message.phone_number_id,
                    )
                    action = ConversationAction(
                        source=source,
                        reply_text=reply,
                        tenant_id=message.tenant_id,
                        phone_number=message.phone_number,
                        metadata=combined_metadata,
                        session_state=session.conversation_state,
                        requires_handoff=flow_result.requires_handoff,
                    )
                    await self._log_interaction(
                        message=message,
                        session_id=session.session_id,
                        flow_used=flow_name,
                        state=state_name,
                        user_message=message.content,
                        bot_response=reply,
                        source=source,
                        started_at=started_at,
                        detected_intent=persisted_intent,
                        execution_context=ctx,
                    )
                    return action

        if flow_result.handled and flow_result.reply_text:
            logger.info("Flow engine resolved message %s with reply", message.message_id)
            hook = (flow_result.metadata or {}).get("hook")
            if isinstance(hook, dict) and hook.get("action") == START_ORDER_ACTION:
                order_action = await self._maybe_order_assistant(message, session, ctx, started_at, trigger=hook)
                if order_action is not None:
                    return order_action
            if await self._should_suppress_auto_reply(message, ctx):
                return self._suppressed_late_reply(message, session, source="flow")
            flow_metadata = flow_result.metadata or {}
            flow_name = self._resolve_flow_name(flow_metadata, session)
            state_name = str(flow_metadata.get("state") or session.current_state or "greeting")

            persisted_intent = self._resolve_persisted_intent(
                intent_result=intent_result,
                fallback_intent=flow_result.detected_intent,
            )
            self._append_message(session, role="assistant", content=flow_result.reply_text)
            session = await self._persist_session_update(
                ctx,
                session,
                state_updates=flow_result.session_state,
                active_flow=flow_name,
                current_state=state_name,
                detected_intent=persisted_intent,
                last_flow=flow_name,
                phone_number_id=message.phone_number_id,
                display_phone_number=message.display_phone_number,
            )
            await self._persist_message(
                ctx,
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
            if flow_result.smart_reentry:
                response_metadata["smart_reentry"] = True
            if flow_result.collected_data:
                response_metadata["collected_data"] = flow_result.collected_data
            if ctx.is_test:
                response_metadata["dry_run"] = True

            # Enrich handoff with context summary
            if flow_result.requires_handoff:
                handoff_summary = self._build_handoff_summary(
                    session=session,
                    intent=persisted_intent,
                    collected_data=flow_result.collected_data or {},
                    contact_name=message.contact_name,
                )
                response_metadata["handoff_summary"] = handoff_summary

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
                execution_context=ctx,
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
            session = await self._persist_session_update(
                ctx,
                session,
                detected_intent=self._resolve_persisted_intent(intent_result=intent_result),
            )
            disabled_metadata: Dict[str, Any] = {"error": "ai_disabled"}
            if ctx.is_test:
                disabled_metadata["dry_run"] = True
            await self._persist_message(
                ctx,
                tenant_id=message.tenant_id,
                session_id=session.session_id,
                direction="outgoing",
                role="assistant",
                content=disabled_reply,
                source="flow",
                metadata=disabled_metadata,
                phone_number_id=message.phone_number_id,
            )
            action = ConversationAction(
                source="flow",
                reply_text=disabled_reply,
                tenant_id=message.tenant_id,
                phone_number=message.phone_number,
                metadata=disabled_metadata,
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
                execution_context=ctx,
            )
            return action

        ai_response = await self.ai_service.generate_response(
            enriched_message,
            session,
            metadata_overrides=tenant_settings.as_ai_metadata(),
        )
        await self._record_ai_usage(message, session, ai_response.metadata, ctx)
        if not ai_response.handled:
            return await self._ai_unavailable_handoff(
                message, session, ai_response.metadata, ctx, source="ai", started_at=started_at
            )
        if await self._should_suppress_auto_reply(message, ctx):
            return self._suppressed_late_reply(message, session, source="ai")
        detected_intent = ai_response.detected_intent or intent_result.intent
        confidence = ai_response.confidence if ai_response.confidence is not None else intent_result.confidence
        persist_intent = detected_intent if detected_intent and confidence > 0.7 else session.detected_intent

        self._append_message(session, role="assistant", content=ai_response.reply_text)
        session = await self._persist_session_update(
            ctx,
            session,
            state_updates=ai_response.session_state,
            detected_intent=persist_intent,
            phone_number_id=message.phone_number_id,
            display_phone_number=message.display_phone_number,
        )
        await self._persist_message(
            ctx,
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
        if ctx.is_test:
            metadata["dry_run"] = True

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
            execution_context=ctx,
        )
        return action

    async def _ai_unavailable_handoff(
        self,
        message: NormalizedMessage,
        session: ConversationSession,
        ai_metadata: Dict[str, Any] | None,
        ctx: ExecutionContext,
        *,
        source: str,
        started_at: float,
    ) -> ConversationAction:
        """Keep the inbound message and route failures to the human queue without sending/billing a reply."""
        context = dict(session.context or {})
        context["human_handoff_pending"] = True
        context["human_handoff_reason"] = str((ai_metadata or {}).get("error") or "ai_unavailable")[:80]
        context["human_handoff_at"] = datetime.utcnow().isoformat()
        context["unread_count"] = int(context.get("unread_count", 0) or 0) + 1
        session = await self._persist_session_update(ctx, session, context_updates=context)
        metadata = {**(ai_metadata or {}), "human_handoff_pending": True, "ai_failure": True}
        if ctx.is_test:
            metadata["dry_run"] = True
        action = ConversationAction(
            source=f"{source}_unavailable", reply_text="", tenant_id=message.tenant_id,
            phone_number=message.phone_number, metadata=metadata,
            session_state=session.conversation_state, requires_handoff=True,
        )
        await self._log_interaction(
            message=message, session_id=session.session_id, flow_used=session.active_flow,
            state=session.current_state, user_message=message.content, bot_response="",
            source=f"{source}_unavailable", started_at=started_at,
            detected_intent=session.detected_intent, execution_context=ctx,
        )
        return action


    async def _maybe_order_assistant(
        self,
        message: NormalizedMessage,
        session: ConversationSession,
        ctx: ExecutionContext,
        started_at: float,
        trigger: Dict[str, Any] | None = None,
    ) -> ConversationAction | None:
        """Let the order assistant own the turn (active draft, purchase intent or flow hook) when Pedidos is on."""
        assistant = getattr(self, "order_assistant", None)
        if assistant is None:
            return None
        tenant_settings = await self.tenant_settings_service.get_or_create(message.tenant_id)
        if not tenant_settings.orders_enabled:
            return None
        try:
            result = await assistant.handle(
                tenant_id=message.tenant_id,
                text=message.content or "",
                context=dict(session.context or {}),
                customer_phone=message.phone_number,
                phone_number_id=message.phone_number_id,
                session_id=session.session_id if ctx.persist else None,
                contact_name=message.contact_name,
                trigger=trigger,
                dry_run=ctx.is_test or not ctx.persist or not ctx.allow_external_side_effects,
            )
        except Exception:
            logger.exception("order_assistant_failed tenant=%s message=%s", message.tenant_id, message.message_id)
            return None
        if result is None:
            return None
        context_updates: Dict[str, Any] = {"order_draft": result.draft}
        if result.order:
            context_updates["last_order_id"] = result.order["id"]
        state_kwargs: Dict[str, Any] = {}
        if result.return_state:
            state_kwargs = {
                "state_updates": {"current_state": result.return_state, "last_state": result.return_state},
                "current_state": result.return_state,
            }
        if not result.reply:
            await self._persist_session_update(ctx, session, context_updates=context_updates, **state_kwargs)
            return None
        if await self._should_suppress_auto_reply(message, ctx):
            return self._suppressed_late_reply(message, session, source="order_assistant")

        metadata: Dict[str, Any] = {"source": "order_assistant", **result.metadata}
        if result.draft:
            metadata["order_stage"] = result.draft.get("stage")
        if ctx.is_test:
            metadata["dry_run"] = True
        self._append_message(session, role="assistant", content=result.reply)
        session = await self._persist_session_update(
            ctx, session, context_updates=context_updates,
            phone_number_id=message.phone_number_id, display_phone_number=message.display_phone_number,
            **state_kwargs,
        )
        await self._persist_message(
            ctx, tenant_id=message.tenant_id, session_id=session.session_id, direction="outgoing",
            role="assistant", content=result.reply, source="order_assistant", metadata=metadata,
            phone_number_id=message.phone_number_id,
        )
        await self._log_interaction(
            message=message, session_id=session.session_id, flow_used=session.active_flow,
            state=session.current_state, user_message=message.content, bot_response=result.reply,
            source="order_assistant", started_at=started_at, detected_intent="pedido", execution_context=ctx,
        )
        return ConversationAction(
            source="order_assistant", reply_text=result.reply, tenant_id=message.tenant_id,
            phone_number=message.phone_number, metadata=metadata,
            session_state=session.conversation_state, requires_handoff=False,
        )

    @staticmethod
    def _is_human_owned(session: ConversationSession) -> bool:
        mode = str(getattr(session, "assignment_mode", None) or "").strip().lower()
        if mode == "human":
            return True
        if mode == "ai":
            return False
        context = session.context or {}
        legacy = str(context.get("assignment_mode") or "").strip().lower()
        if legacy == "human":
            return True
        return bool(context.get("human_handoff_pending")) and bool(
            context.get("assigned_user_id") or context.get("assumed_by")
        )

    async def _should_suppress_auto_reply(
        self,
        message: NormalizedMessage,
        ctx: ExecutionContext,
    ) -> bool:
        if not ctx.persist:
            return False
        fresh = await self.session_service.repository.get_session(
            message.tenant_id,
            message.phone_number,
        )
        if fresh is None:
            return False
        return self._is_human_owned(fresh)

    def _suppressed_late_reply(
        self,
        message: NormalizedMessage,
        session: ConversationSession,
        *,
        source: str,
    ) -> ConversationAction:
        logger.info(
            "Suppressing late auto-reply (%s) for %s — conversation is human-owned",
            source,
            message.message_id,
        )
        return ConversationAction(
            source="suppressed_late_ai",
            reply_text="",
            tenant_id=message.tenant_id,
            phone_number=message.phone_number,
            metadata={
                "suppressed_late_ai": True,
                "original_source": source,
                "assignment_mode": "human",
            },
            session_state=session.conversation_state,
            requires_handoff=True,
        )

    async def _ensure_operational_defaults(self, session: ConversationSession) -> ConversationSession:
        changed = False
        if not getattr(session, "assignment_mode", None):
            session.assignment_mode = "ai"
            changed = True
        context = dict(session.context or {})
        if "assignment_mode" not in context:
            context["assignment_mode"] = session.assignment_mode or "ai"
            changed = True
        if not session.group_id and not context.get("group_id"):
            context.setdefault("group_name", "Geral")
            changed = True
        if changed:
            session.context = context
            return await self.session_service.update_session(session)
        return session

    async def _resolve_session(
        self,
        message: NormalizedMessage,
        ctx: ExecutionContext,
    ) -> ConversationSession:
        if not ctx.persist:
            return ConversationSession(
                tenant_id=message.tenant_id,
                phone_number=message.phone_number,
                phone_number_id=message.phone_number_id,
                display_phone_number=message.display_phone_number,
            )
        return await self.session_service.get_or_create_session(
            message.tenant_id,
            message.phone_number,
            phone_number_id=message.phone_number_id,
            display_phone_number=message.display_phone_number,
        )

    async def _persist_session_update(
        self,
        ctx: ExecutionContext,
        session: ConversationSession,
        **kwargs: Any,
    ) -> ConversationSession:
        if not ctx.persist:
            state_updates = kwargs.get("state_updates")
            context_updates = kwargs.get("context_updates")
            if state_updates:
                session.conversation_state.update(state_updates)
            if context_updates:
                session.context.update(context_updates)
            if kwargs.get("last_flow"):
                session.last_flow = kwargs["last_flow"]
            if "active_flow" in kwargs and kwargs["active_flow"] is not None:
                session.active_flow = kwargs["active_flow"]
            if "current_state" in kwargs and kwargs["current_state"] is not None:
                session.current_state = kwargs["current_state"]
            if "detected_intent" in kwargs and kwargs["detected_intent"] is not None:
                session.detected_intent = kwargs["detected_intent"]
            if kwargs.get("phone_number_id") is not None:
                session.phone_number_id = kwargs["phone_number_id"]
            if kwargs.get("display_phone_number") is not None:
                session.display_phone_number = kwargs["display_phone_number"]
            session.touch()
            return session
        return await self.session_service.update_session(session, **kwargs)

    async def _persist_message(self, ctx: ExecutionContext, **kwargs: Any) -> None:
        if not ctx.persist:
            return
        await self.message_service.append(**kwargs)

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

    @staticmethod
    def _compose_ai_fallback_reply(
        ai_reply: str,
        flow_state_message: str | None,
    ) -> str:
        """Merge a natural AI intro with the canonical flow-state body."""
        flow_msg = (flow_state_message or "").strip()
        ai_reply = (ai_reply or "").strip()
        if not flow_msg:
            return ai_reply
        if not ai_reply:
            return flow_msg
        # A complete answer stands alone: appending the state message re-sent the greeting and the whole menu
        # after every free-form question. Only a reply cut off mid-markup is completed with the canonical body.
        if not ConversationService._looks_truncated(ai_reply):
            return ai_reply
        if ConversationService._flow_content_in_reply(ai_reply, flow_msg):
            return ai_reply
        intro = ConversationService._extract_fallback_intro(ai_reply, flow_msg)
        if intro:
            return f"{intro}\n\n{flow_msg}"
        return flow_msg

    @staticmethod
    def _looks_truncated(ai_reply: str) -> bool:
        tail = ai_reply.rstrip()
        return bool(re.search(r"(?:[*:_~`,\-–—]|[🗓📍🛵⏰])\s*$", tail, flags=re.UNICODE))

    _TRANSIENT_HANDOFF_PREFIXES = ("local_ai_", "gemini_", "openai_", "ai_")

    @classmethod
    def _clear_transient_ai_handoff(cls, session) -> None:
        """A successful AI reply resolves a handoff that only an AI failure had raised."""
        if str(getattr(session, "assignment_mode", "") or "ai").lower() != "ai" or getattr(session, "assigned_user_id", None):
            return
        context = dict(session.context or {})
        reason = str(context.get("human_handoff_reason") or "")
        if context.get("human_handoff_pending") and reason.startswith(cls._TRANSIENT_HANDOFF_PREFIXES):
            for key in ("human_handoff_pending", "human_handoff_reason", "human_handoff_at"):
                context.pop(key, None)
            session.context = context

    @staticmethod
    def _flow_content_in_reply(ai_reply: str, flow_msg: str) -> bool:
        anchors: list[str] = []
        for line in flow_msg.splitlines():
            cleaned = re.sub(r"[*_~`]", "", line).strip()
            if len(cleaned) >= 12:
                anchors.append(cleaned[:40].lower())
        if not anchors:
            return len(ai_reply) >= int(len(flow_msg) * 0.85)
        hits = sum(1 for anchor in anchors if anchor in ai_reply.lower())
        return hits >= max(1, min(2, len(anchors) // 2))

    @staticmethod
    def _extract_fallback_intro(ai_reply: str, flow_msg: str) -> str:
        intro = re.sub(r"[*🗓📍🛵⏰]+\s*$", "", ai_reply, flags=re.UNICODE).strip()
        intro = re.sub(r"\*+\s*$", "", intro).strip()

        flow_lines_plain = [
            re.sub(r"[*_~`]", "", line).strip().lower()
            for line in flow_msg.splitlines()
            if line.strip()
        ]

        kept: list[str] = []
        for line in intro.splitlines():
            plain = re.sub(r"[*_~`]", "", line).strip().lower()
            if not plain or len(plain) <= 2:
                continue
            if any(
                plain in flow_line or flow_line.startswith(plain[:30])
                for flow_line in flow_lines_plain
                if len(flow_line) > 10
            ):
                break
            if plain.endswith(":") and not any(ch.isdigit() for ch in plain):
                continue
            kept.append(line.rstrip())

        result = "\n".join(kept).strip()
        if result:
            return result
        first_line = intro.split("\n")[0].strip()
        return first_line

    @staticmethod
    def _resolve_flow_name(flow_metadata: Dict[str, Any], session) -> str | None:
        raw = None
        if isinstance(flow_metadata, dict):
            raw = flow_metadata.get("flow")
        if not raw:
            raw = getattr(session, "active_flow", None)
        if isinstance(raw, str) and raw.strip():
            return raw.strip()
        return None

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
        execution_context: ExecutionContext | None = None,
    ) -> None:
        ctx = execution_context or ExecutionContext.production()
        if not ctx.persist:
            return
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

    def _build_handoff_summary(
        self,
        session,
        intent: str | None,
        collected_data: Dict[str, Any] | None,
        contact_name: str | None,
    ) -> str:
        """Build a human-readable summary to send to the human agent."""
        lines = ["*Resumo do atendimento automatizado:*"]
        if contact_name:
            lines.append(f"• Cliente: {contact_name}")
        if intent:
            lines.append(f"• Intenção identificada: {intent}")
        if collected_data:
            for key, value in collected_data.items():
                lines.append(f"• {key}: {value}")
        history = list(getattr(session, "conversation_history", []))
        if history:
            last_msgs = history[-4:]  # last 2 exchanges
            lines.append("\n*Últimas mensagens:*")
            for msg in last_msgs:
                role_label = "Usuário" if getattr(msg, "role", "") == "user" else "Bot"
                content = (getattr(msg, "content", "") or "")[:120]
                lines.append(f"  [{role_label}] {content}")
        return "\n".join(lines)

