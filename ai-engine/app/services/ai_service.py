"""AI orchestration service."""
from __future__ import annotations

import json
import logging
import re
from datetime import date
from typing import Any, Dict, List

from app.clients.openai_client import (
    OpenAIAuthError,
    OpenAIClient,
    OpenAIClientError,
    OpenAIRateLimitError,
    OpenAIServerError,
)
from app.clients.gemini_client import (
    GeminiAuthError,
    GeminiClient,
    GeminiClientError,
    GeminiRateLimitError,
    GeminiServerError,
)
from app.config.settings import settings
from app.domain.message import AIReply, AIRequestPayload, AIResponsePayload, ChatMessage, IntentAnalysis
from app.services.intent_service import IntentService

logger = logging.getLogger(__name__)


class AIService:
    """Builds prompts, calls model providers, and returns structured replies."""

    _REALTIME_PATTERN = re.compile(
        r"\b("
        r"agora|hoje|ontem|ultim[oa]|ao vivo|tempo real|resultado|placar|jogo|partida|"
        r"cotacao|dolar|bitcoin|noticia|noticias|clima|temperatura|acao|acoes|bolsa"
        r")\b",
        re.I,
    )

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

    async def detect_intent(self, text: str) -> IntentAnalysis:
        return self.intent_service.classify(text or "")

    async def generate(self, payload: AIRequestPayload) -> AIResponsePayload:
        if self.mock_enabled:
            logger.info("MOCK_AI enabled, returning simulated response")
            return self._mock_response(payload.session_state)

        metadata = self._extract_metadata(payload.metadata)
        user_text = payload.latest_text
        intent = self.intent_service.classify(user_text)
        prompt = self._build_prompt(payload.context, user_text, intent, payload.metadata)
        preferred_model = self._normalize_model_name(metadata.get("ai_model"))
        fallback_models = self._normalize_model_list(metadata.get("ai_fallback_models"))
        debug_enabled = bool(settings.AI_DEBUG_PROMPTS or metadata.get("debug_mode"))

        if settings.BLOCK_REALTIME_FACTS and self._looks_like_realtime_question(user_text):
            logger.info("Realtime guard triggered tenant=%s session=%s", payload.tenant_id, payload.session_id)
            return AIResponsePayload(
                handled=True,
                intent="realtime_guard",
                confidence=1.0,
                reply=AIReply(content=settings.REALTIME_GUARD_REPLY),
                session_state=payload.session_state,
                metadata={
                    "source": "guardrail",
                    "reason": "realtime_fact_block",
                    "tenant_id": payload.tenant_id,
                },
            )

        logger.info(
            "Generating AI response tenant=%s session=%s intent=%s",
            payload.tenant_id,
            payload.session_id,
            intent.intent,
        )
        if debug_enabled:
            logger.info(
                "AI DEBUG prompt tenant=%s session=%s payload=%s",
                payload.tenant_id,
                payload.session_id,
                json.dumps(prompt, ensure_ascii=False),
            )

        selected_model: str | None = None
        model_attempts: List[Dict[str, Any]] = []

        try:
            if self.provider == "openai":
                completion = await self.openai_client.create_chat_completion(prompt)
                reply_content = self._extract_openai_reply(completion)
                source = "openai"
            else:
                today = date.today().strftime("%d/%m/%Y")
                system_prompt_with_date = f"Hoje e {today}.\n{settings.SYSTEM_PROMPT}"
                completion = await self.gemini_client.generate_content(
                    system_prompt=system_prompt_with_date,
                    messages=prompt,
                    preferred_model=preferred_model,
                    fallback_models=fallback_models,
                )
                reply_content = self._extract_gemini_reply(completion)
                source = "gemini"
                selected_model = self.gemini_client.resolved_model
                model_attempts = self.gemini_client.last_attempts
        except OpenAIAuthError:
            logger.error("OpenAI authentication failed; check API key")
            return self._unavailable_response(payload.session_state, error="openai_auth_error", retryable=False)
        except OpenAIRateLimitError:
            logger.warning("OpenAI quota or rate limit exceeded")
            return self._unavailable_response(payload.session_state, error="openai_rate_limit", retryable=True)
        except OpenAIServerError:
            logger.error("OpenAI service returned 5xx")
            return self._unavailable_response(payload.session_state, error="openai_server_error", retryable=True)
        except OpenAIClientError:
            logger.exception("OpenAI client error")
            return self._unavailable_response(payload.session_state, error="openai_client_error", retryable=False)
        except GeminiAuthError as exc:
            logger.error("Gemini authentication failed; check API key")
            return self._unavailable_response(
                payload.session_state,
                error="gemini_auth_error",
                retryable=False,
                metadata={"model_attempts": exc.model_attempts},
            )
        except GeminiRateLimitError as exc:
            logger.warning("Gemini quota or rate limit exceeded")
            return self._unavailable_response(
                payload.session_state,
                error="gemini_rate_limit",
                retryable=True,
                metadata={"model_attempts": exc.model_attempts},
            )
        except GeminiServerError as exc:
            logger.error("Gemini service returned 5xx")
            return self._unavailable_response(
                payload.session_state,
                error="gemini_server_error",
                retryable=True,
                metadata={"model_attempts": exc.model_attempts},
            )
        except GeminiClientError as exc:
            logger.exception("Gemini client error")
            return self._unavailable_response(
                payload.session_state,
                error="ai_all_models_unavailable",
                retryable=bool(exc.retryable),
                metadata={"model_attempts": exc.model_attempts},
            )

        response_metadata: Dict[str, Any] = {"source": source, "tenant_id": payload.tenant_id}
        if source == "gemini":
            response_metadata["model_used"] = selected_model
            response_metadata["model_attempts"] = model_attempts
        if debug_enabled:
            response_metadata["debug_mode"] = True
            logger.info(
                "AI DEBUG response tenant=%s session=%s source=%s model=%s reply=%s",
                payload.tenant_id,
                payload.session_id,
                source,
                selected_model,
                reply_content,
            )

        return AIResponsePayload(
            handled=True,
            intent=intent.intent,
            confidence=intent.confidence,
            reply=AIReply(content=reply_content),
            session_state=payload.session_state,
            metadata=response_metadata,
        )

    def _build_prompt(
        self,
        context: List[ChatMessage],
        user_text: str,
        intent: IntentAnalysis,
        metadata: Dict[str, Any] | None = None,
    ) -> List[dict]:
        trimmed_context = context[-settings.MAX_HISTORY_MESSAGES :]

        # Build a context-aware system message
        context_lines = [f"Intenção detectada: {intent.intent}"]

        meta = metadata or {}

        # Include current flow state message as context
        flow_state_msg = meta.get("flow_state_message")
        if flow_state_msg:
            context_lines.append(
                f"Contexto do fluxo atual: {flow_state_msg.strip()}"
            )

        # Include available options as natural suggestions (not commands)
        options: List[Any] = meta.get("options") or []
        if options:
            opt_labels = [
                opt.get("label") or opt.get("value", "")
                for opt in options
                if isinstance(opt, dict)
            ]
            opt_labels = [str(o).strip() for o in opt_labels if o]
            if opt_labels:
                context_lines.append(
                    "Opções disponíveis (mencione como sugestões naturais, "
                    "não como lista numerada ou menu): "
                    + ", ".join(f'"{o}"' for o in opt_labels)
                )

        # Include already-collected data so AI doesn't re-ask
        collected: Dict[str, Any] = meta.get("collected_data") or {}
        if collected:
            items = "; ".join(f"{k}: {v}" for k, v in collected.items())
            context_lines.append(
                f"Informações já coletadas (NÃO pergunte novamente): {items}"
            )

        # Natural language style instructions
        context_lines.append(
            "Responda de forma natural e conversacional, como um atendente humano "
            "simpático. Evite frases como 'Escolha uma opção' ou 'Digite o número'. "
            "Prefira 'Posso te mostrar...', 'Quer que eu te ajude com...' ou "
            "'Que tal...'. Seja breve e direto."
        )

        system_content = "\n".join(context_lines)
        messages = [{"role": "system", "content": system_content}]
        for message in trimmed_context:
            messages.append(message.model_dump())
        messages.append({"role": "user", "content": user_text})
        return messages

    def _extract_openai_reply(self, completion: dict) -> str:
        choices = completion.get("choices", [])
        if not choices:
            logger.warning("OpenAI completion returned no choices")
            return "Desculpe, nao consegui gerar uma resposta agora."
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
            return "Desculpe, nao consegui gerar uma resposta agora."
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
            reply=AIReply(content="(Mock) Como posso ajudar?"),
            session_state=session_state or {},
            metadata={"source": "mock"},
        )

    def _unavailable_response(
        self,
        session_state: Dict[str, Any] | None,
        *,
        error: str = "ai_unavailable",
        retryable: bool = False,
        metadata: Dict[str, Any] | None = None,
    ) -> AIResponsePayload:
        result_metadata = {"source": "ai_engine"}
        if metadata:
            result_metadata.update(metadata)
        return AIResponsePayload(
            handled=False,
            error=error,
            retryable=retryable,
            session_state=session_state or {},
            metadata=result_metadata,
        )

    def _looks_like_realtime_question(self, text: str) -> bool:
        return bool(self._REALTIME_PATTERN.search(text or ""))

    def _extract_metadata(self, metadata: Dict[str, Any] | None) -> Dict[str, Any]:
        return dict(metadata) if isinstance(metadata, dict) else {}

    def _normalize_model_name(self, value: Any) -> str | None:
        if not isinstance(value, str):
            return None
        item = value.strip()
        if not item:
            return None
        if item.startswith("models/"):
            item = item.split("models/", 1)[1]
        return item

    def _normalize_model_list(self, value: Any) -> List[str]:
        if not isinstance(value, list):
            return []
        unique: List[str] = []
        for item in value:
            normalized = self._normalize_model_name(item)
            if normalized and normalized not in unique:
                unique.append(normalized)
        return unique

