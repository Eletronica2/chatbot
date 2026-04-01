"""Service responsible for delegating to the AI engine."""
from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any, Dict

import httpx

from app.domain.message import AIResponse, NormalizedMessage
from app.domain.session import ConversationSession

logger = logging.getLogger(__name__)


@dataclass
class IntentDetectionResult:
    intent: str | None = None
    confidence: float = 0.0
    provider: str = "none"


class AIService:
    """Communicates with the AI engine to generate responses and intents."""

    def __init__(self, base_url: str, timeout: int = 20):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    async def detect_intent(
        self,
        *,
        tenant_id: str,
        phone_number: str,
        text: str,
        session_state: Dict[str, Any] | None = None,
    ) -> IntentDetectionResult:
        payload: Dict[str, Any] = {
            "tenant_id": tenant_id,
            "phone_number": phone_number,
            "text": text,
            "session_state": session_state or {},
        }
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(
                    f"{self.base_url}/ai/intent",
                    json=payload,
                )
            if response.status_code >= 400:
                return IntentDetectionResult()

            data = response.json() if response.content else {}
            raw_intent = data.get("intent")
            raw_confidence = data.get("confidence", 0.0)
            intent = (
                str(raw_intent).strip()
                if isinstance(raw_intent, str) and raw_intent.strip()
                else None
            )
            try:
                confidence = float(raw_confidence or 0.0)
            except (TypeError, ValueError):
                confidence = 0.0
            return IntentDetectionResult(
                intent=intent,
                confidence=confidence,
                provider=str(data.get("provider") or "ai-engine"),
            )
        except Exception as exc:  # pragma: no cover - defensive fallback
            logger.debug("Intent detection unavailable: %s", exc)
            return IntentDetectionResult()

    async def generate_response(
        self,
        message: NormalizedMessage,
        session: ConversationSession,
        metadata_overrides: Dict[str, Any] | None = None,
    ) -> AIResponse:
        merged_metadata: Dict[str, Any] = {}
        if isinstance(message.metadata, dict):
            merged_metadata.update(message.metadata)
        if isinstance(metadata_overrides, dict):
            merged_metadata.update(metadata_overrides)

        payload: Dict[str, Any] = {
            "tenant_id": message.tenant_id,
            "phone_number": message.phone_number,
            "message": message.content,
            "context": session.context,
            "session_state": session.conversation_state,
            "metadata": merged_metadata,
        }

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(
                    f"{self.base_url}/ai/respond",
                    json=payload,
                )

            response.raise_for_status()
            data = response.json() if response.content else {}
            logger.info("AI engine responded for message %s", message.message_id)
            metadata = data.get("metadata") if isinstance(data.get("metadata"), dict) else {}
            raw_confidence = data.get("confidence", metadata.get("confidence"))
            confidence: float | None = None
            if raw_confidence is not None:
                try:
                    confidence = float(raw_confidence)
                except (TypeError, ValueError):
                    confidence = None

            detected_intent = (
                data.get("detected_intent")
                or data.get("intent")
                or metadata.get("detected_intent")
                or metadata.get("intent")
            )

            return AIResponse(
                handled=bool(data.get("handled", True)),
                reply_text=str(data.get("reply_text", "")),
                detected_intent=(
                    str(detected_intent)
                    if isinstance(detected_intent, str) and detected_intent.strip()
                    else None
                ),
                confidence=confidence,
                session_state=data.get("session_state"),
                metadata=metadata,
            )

        except httpx.HTTPStatusError as exc:
            logger.warning("AI engine rejected request: %s", exc)
            return AIResponse(
                handled=False,
                reply_text="Desculpe, nao consegui entender sua solicitacao agora.",
                metadata={"error": "ai_engine_status"},
            )
        except httpx.RequestError as exc:
            logger.error("AI engine offline: %s", exc)
            return AIResponse(
                handled=False,
                reply_text="No momento nao consigo responder, tente novamente em instantes.",
                metadata={"error": "ai_engine_unreachable"},
            )
        except Exception as exc:  # pragma: no cover - safeguard
            logger.exception("Unexpected AI service error: %s", exc)
            return AIResponse(
                handled=False,
                reply_text="Ocorreu um erro interno. Nossa equipe ja foi notificada.",
                metadata={"error": "ai_engine_exception"},
            )

