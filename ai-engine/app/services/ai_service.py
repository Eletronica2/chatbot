"""AI orchestration service"""
from __future__ import annotations

import logging
from datetime import date
from typing import Any, Dict, List

from app.clients.openai_client import (
    OpenAIAuthError,
    OpenAIClientError,
    OpenAIRateLimitError,
    OpenAIServerError,
    OpenAIClient,
)
from app.clients.gemini_client import (
    GeminiAuthError,
    GeminiClient,
    GeminiClientError,
    GeminiRateLimitError,
    GeminiServerError,
)
from app.config.settings import settings
from app.domain.message import (
    AIReply,
    AIRequestPayload,
    AIResponsePayload,
    ChatMessage,
    IntentAnalysis,
)
from app.services.intent_service import IntentService

logger = logging.getLogger(__name__)


class AIService:
    """Builds prompts, calls OpenAI, and returns structured replies"""

    def __init__(
        self,
        openai_client: OpenAIClient,
        gemini_client: GeminiClient,
        intent_service: IntentService,
    ):
        self.openai_client = openai_client
        self.gemini_client = gemini_client
        self.intent_service = intent_service
        self.mock_enabled = settings.MOCK_AI
        self.provider = settings.AI_PROVIDER.lower().strip()

    async def generate(self, payload: AIRequestPayload) -> AIResponsePayload:
        if self.mock_enabled:
            logger.info("MOCK_AI enabled, returning simulated response")
            return self._mock_response(payload.session_state)

        user_text = payload.latest_text
        intent = self.intent_service.classify(user_text)
        prompt = self._build_prompt(payload.context, user_text, intent)

        logger.info(
            "Generating AI response tenant=%s session=%s intent=%s",
            payload.tenant_id,
            payload.session_id,
            intent.intent,
        )

        try:
            if self.provider == "openai":
                completion = await self.openai_client.create_chat_completion(prompt)
                reply_content = self._extract_openai_reply(completion)
                source = "openai"
            else:
                today = date.today().strftime("%d/%m/%Y")
                system_prompt_with_date = (
                    f"Hoje é {today}.\n{settings.SYSTEM_PROMPT}"
                )
                completion = await self.gemini_client.generate_content(
                    system_prompt=system_prompt_with_date,
                    messages=prompt,
                )
                reply_content = self._extract_gemini_reply(completion)
                source = "gemini"
        except OpenAIAuthError:
            logger.error("OpenAI authentication failed; check API key")
            return self._unavailable_response(payload.session_state)
        except OpenAIRateLimitError:
            logger.warning("OpenAI quota or rate limit exceeded")
            return self._unavailable_response(payload.session_state)
        except OpenAIServerError:
            logger.error("OpenAI service returned 5xx")
            return self._unavailable_response(payload.session_state)
        except OpenAIClientError:
            logger.exception("OpenAI client error")
            return self._unavailable_response(payload.session_state)
        except GeminiAuthError:
            logger.error("Gemini authentication failed; check API key")
            return self._unavailable_response(payload.session_state)
        except GeminiRateLimitError:
            logger.warning("Gemini quota or rate limit exceeded")
            return self._unavailable_response(payload.session_state)
        except GeminiServerError:
            logger.error("Gemini service returned 5xx")
            return self._unavailable_response(payload.session_state)
        except GeminiClientError:
            logger.exception("Gemini client error")
            return self._unavailable_response(payload.session_state)

        return AIResponsePayload(
            handled=True,
            intent=intent.intent,
            confidence=intent.confidence,
            reply=AIReply(content=reply_content),
            session_state=payload.session_state,
            metadata={"source": source, "tenant_id": payload.tenant_id},
        )

    def _build_prompt(
        self,
        context: List[ChatMessage],
        user_text: str,
        intent: IntentAnalysis,
    ) -> List[dict]:
        trimmed_context = context[-settings.MAX_HISTORY_MESSAGES :]
        messages = [{"role": "system", "content": f"Intent atual: {intent.intent}"}]
        for message in trimmed_context:
            messages.append(message.model_dump())
        messages.append({"role": "user", "content": user_text})
        return messages

    def _extract_openai_reply(self, completion: dict) -> str:
        choices = completion.get("choices", [])
        if not choices:
            logger.warning("OpenAI completion returned no choices")
            return "Desculpe, não consegui gerar uma resposta agora."
        first_choice = choices[0]
        message = first_choice.get("message", {})
        content = message.get("content")
        if not content:
            return "Desculpe, estou com dificuldades em responder."
        return content.strip()

    def _extract_gemini_reply(self, completion: dict) -> str:
        candidates = completion.get("candidates", [])
        if not candidates:
            logger.warning("Gemini completion returned no candidates")
            return "Desculpe, não consegui gerar uma resposta agora."
        first = candidates[0]
        content = first.get("content", {})
        parts = content.get("parts", []) if isinstance(content, dict) else []
        if not parts:
            return "Desculpe, estou com dificuldades em responder."
        text_parts = [str(part.get("text", "")).strip() for part in parts if isinstance(part, dict)]
        text = "\n".join(part for part in text_parts if part)
        return text or "Desculpe, estou com dificuldades em responder."

    def _mock_response(self, session_state: Dict[str, Any] | None) -> AIResponsePayload:
        return AIResponsePayload(
            handled=True,
            intent="mock",
            confidence=0.9,
            reply=AIReply(content="🤖 (Mock) Como posso ajudar?"),
            session_state=session_state or {},
            metadata={"source": "mock"},
        )

    def _unavailable_response(self, session_state: Dict[str, Any] | None) -> AIResponsePayload:
        return AIResponsePayload(
            handled=False,
            error="ai_unavailable",
            retryable=False,
            session_state=session_state or {},
            metadata={"source": "ai_engine"},
        )
