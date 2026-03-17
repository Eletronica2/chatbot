"""AI API endpoints"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Dict, List

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, ValidationError

from app.config.settings import settings
from app.domain.message import AIRequestPayload, AIResponsePayload, ChatMessage
from app.services.ai_service import AIService
from app.services.dependencies import get_ai_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ai", tags=["AI"])


class LegacyAIRespondPayload(BaseModel):
    tenant_id: str
    phone_number: str
    message: Any
    context: Dict[str, Any] = Field(default_factory=dict)
    session_state: Dict[str, Any] = Field(default_factory=dict)
    metadata: Dict[str, Any] | None = None


class LegacyAIRespondResponse(BaseModel):
    reply_text: str
    session_state: Dict[str, Any] = Field(default_factory=dict)
    metadata: Dict[str, Any] = Field(default_factory=dict)


@router.post("/generate", response_model=AIResponsePayload)
async def generate_response(
    payload: AIRequestPayload,
    ai_service: AIService = Depends(get_ai_service),
) -> AIResponsePayload:
    try:
        return await ai_service.generate(payload)
    except Exception as exc:  # pragma: no cover - defensive guard
        logger.exception("AI generation failed: %s", exc)
        raise HTTPException(status_code=500, detail="AI generation error") from exc


@router.post("/respond", response_model=LegacyAIRespondResponse)
async def respond(
    payload: LegacyAIRespondPayload,
    ai_service: AIService = Depends(get_ai_service),
) -> LegacyAIRespondResponse:
    normalized_request = _build_internal_payload(payload)
    result = await ai_service.generate(normalized_request)
    return _to_legacy_response(result)


@router.get("/health")
async def health_check() -> dict:
    return {
        "status": "healthy",
        "service": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "timestamp": datetime.utcnow().isoformat(),
    }


def _build_internal_payload(payload: LegacyAIRespondPayload) -> AIRequestPayload:
    message_content: Any = payload.message
    if isinstance(message_content, str):
        message_content = {"text": message_content}

    context_messages = _coerce_context(payload.context)

    return AIRequestPayload(
        tenant_id=payload.tenant_id,
        phone_number=payload.phone_number,
        message=message_content,
        context=context_messages,
        session_state=payload.session_state,
        metadata=payload.metadata,
    )


def _coerce_context(raw_context: Dict[str, Any]) -> List[ChatMessage]:
    candidates: List[Any] = []
    if isinstance(raw_context, list):
        candidates = raw_context
    elif isinstance(raw_context, dict):
        for key in ("messages", "history", "items"):
            value = raw_context.get(key)
            if isinstance(value, list):
                candidates = value
                break

    normalized: List[ChatMessage] = []
    for item in candidates:
        if not isinstance(item, dict):
            continue
        role = item.get("role")
        content = item.get("content")
        if not isinstance(role, str) or not isinstance(content, str):
            continue
        try:
            normalized.append(ChatMessage(role=role, content=content))
        except ValidationError:
            continue
    return normalized


def _to_legacy_response(result: AIResponsePayload) -> LegacyAIRespondResponse:
    if result.handled and result.reply:
        metadata = dict(result.metadata or {})
        if result.intent:
            metadata.setdefault("intent", result.intent)
        if result.confidence is not None:
            metadata.setdefault("confidence", result.confidence)
        return LegacyAIRespondResponse(
            reply_text=result.reply.content,
            session_state=result.session_state,
            metadata=metadata,
        )

    metadata = dict(result.metadata or {})
    error_code = result.error or "ai_unavailable"
    metadata.update({"error": error_code, "retryable": bool(result.retryable)})
    fallback_reply = "Desculpe, não consigo responder agora."
    return LegacyAIRespondResponse(
        reply_text=fallback_reply,
        session_state=result.session_state,
        metadata=metadata,
    )
