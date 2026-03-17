"""Service responsible for delegating to the AI engine"""
from __future__ import annotations

import logging
from typing import Any, Dict

import httpx

from app.domain.message import AIResponse, NormalizedMessage
from app.domain.session import ConversationSession

logger = logging.getLogger(__name__)


class AIService:
    """Communicates with the AI engine to generate responses"""

    def __init__(self, base_url: str, timeout: int = 20):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    async def generate_response(
        self,
        message: NormalizedMessage,
        session: ConversationSession,
    ) -> AIResponse:
        payload: Dict[str, Any] = {
            "tenant_id": message.tenant_id,
            "phone_number": message.phone_number,
            "message": message.content,
            "context": session.context,
            "session_state": session.conversation_state,
            "metadata": message.metadata,
        }

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(
                    f"{self.base_url}/ai/respond",
                    json=payload,
                )

            response.raise_for_status()
            data = response.json()
            logger.info("AI engine responded for message %s", message.message_id)
            return AIResponse(
                reply_text=data.get("reply_text", ""),
                session_state=data.get("session_state"),
                metadata=data.get("metadata"),
            )

        except httpx.HTTPStatusError as exc:
            logger.warning("AI engine rejected request: %s", exc)
            return AIResponse(
                reply_text="Desculpe, não consegui entender sua solicitação agora.",
                metadata={"error": "ai_engine_status"},
            )
        except httpx.RequestError as exc:
            logger.error("AI engine offline: %s", exc)
            return AIResponse(
                reply_text="No momento não consigo responder, tente novamente em instantes.",
                metadata={"error": "ai_engine_unreachable"},
            )
        except Exception as exc:  # pragma: no cover - safeguard
            logger.exception("Unexpected AI service error: %s", exc)
            return AIResponse(
                reply_text="Ocorreu um erro interno. Nossa equipe já foi notificada.",
                metadata={"error": "ai_engine_exception"},
            )
