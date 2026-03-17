"""Wrapper around Google Gemini generateContent API"""
from __future__ import annotations

import json
import logging
import re
from typing import Any, Dict, List, Optional

import httpx

from app.config.settings import settings

logger = logging.getLogger(__name__)

# Ordered redundancy chain requested before generic fallback.
DEFAULT_MODEL_CHAIN: List[str] = [
    "gemini-2.5-flash",
    "gemini-2.0-flash",
    "gemini-1.5-flash",
    "gemini-1.0-pro",
    "gemini-pro",
    "gemini-1.5-pro",
    "gemini-2.0-pro",
    "gemini-2.5-flash",
    "gemini-2.0-flash",
    "gemini-2.0-flash-lite",
    "gemini-1.5-flash-latest",
    "gemini-1.5-pro-latest",
]


class GeminiClientError(Exception):
    """Base error for Gemini client issues"""

    def __init__(
        self,
        message: str,
        status_code: Optional[int] = None,
        retryable: bool = False,
        model_attempts: Optional[List[Dict[str, Any]]] = None,
    ):
        super().__init__(message)
        self.status_code = status_code
        self.retryable = retryable
        self.model_attempts = list(model_attempts or [])


class GeminiAuthError(GeminiClientError):
    pass


class GeminiRateLimitError(GeminiClientError):
    pass


class GeminiServerError(GeminiClientError):
    pass


class GeminiClient:
    """Simple HTTP client for Gemini generateContent"""

    def __init__(self, api_key: str | None = None, model: str | None = None):
        self.api_key = api_key or settings.GEMINI_API_KEY
        self.model = self._normalize_model_name(model or settings.GEMINI_MODEL)
        self.timeout = settings.GEMINI_TIMEOUT
        self._resolved_model: str | None = None
        self._last_attempts: List[Dict[str, Any]] = []

    async def generate_content(
        self,
        system_prompt: str,
        messages: List[Dict[str, str]],
        preferred_model: str | None = None,
        fallback_models: List[str] | None = None,
    ) -> Dict[str, Any]:
        if not self.api_key:
            raise GeminiAuthError("Missing GEMINI_API_KEY")

        payload = {
            "systemInstruction": {"parts": [{"text": system_prompt}]},
            "contents": self._to_gemini_contents(messages),
            "generationConfig": {
                "temperature": 0.5,
                "maxOutputTokens": 400,
            },
        }

        preferred_models = self._build_preferred_models(
            preferred_model=preferred_model,
            fallback_models=fallback_models,
        )
        self._last_attempts = []

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                for idx, candidate_model in enumerate(preferred_models):
                    try:
                        if settings.AI_DEBUG_PROMPTS:
                            logger.info(
                                "Gemini debug request model=%s payload=%s",
                                candidate_model,
                                self._build_debug_payload_snapshot(payload),
                            )

                        response = await client.post(
                            f"https://generativelanguage.googleapis.com/v1beta/models/{candidate_model}:generateContent",
                            headers={
                                "x-goog-api-key": self.api_key,
                                "Content-Type": "application/json",
                            },
                            json=payload,
                        )
                        response.raise_for_status()
                        self._resolved_model = candidate_model
                        self._last_attempts.append(
                            {"model": candidate_model, "status": response.status_code}
                        )
                        data = response.json()
                        if settings.AI_DEBUG_PROMPTS:
                            logger.info(
                                "Gemini debug response model=%s preview=%s",
                                candidate_model,
                                self._build_debug_response_snapshot(data),
                            )
                        return data
                    except httpx.HTTPStatusError as exc:
                        status = exc.response.status_code
                        text = exc.response.text
                        self._last_attempts.append({"model": candidate_model, "status": status})

                        if status in (404, 429) and idx < len(preferred_models) - 1:
                            logger.warning(
                                "Gemini model '%s' returned status %s, trying next candidate",
                                candidate_model,
                                status
                            )
                            continue

                        logger.error("Gemini API error: %s - %s", status, text)
                        if status in (401, 403):
                            raise GeminiAuthError(
                                "Invalid Gemini credentials",
                                status_code=status,
                                model_attempts=self._last_attempts,
                            ) from exc
                        if status == 429:
                            raise GeminiRateLimitError(
                                "Gemini quota/rate limit exceeded",
                                status_code=status,
                                model_attempts=self._last_attempts,
                            ) from exc
                        if status >= 500:
                            raise GeminiServerError(
                                "Gemini service unavailable",
                                status_code=status,
                                model_attempts=self._last_attempts,
                            ) from exc
                        raise GeminiClientError(
                            "Unexpected Gemini error",
                            status_code=status,
                            model_attempts=self._last_attempts,
                        ) from exc

                final_status = self._last_attempts[-1]["status"] if self._last_attempts else 404
                retryable = any(row.get("status") == 429 for row in self._last_attempts)
                raise GeminiClientError(
                    "All configured Gemini models failed",
                    status_code=final_status,
                    retryable=retryable,
                    model_attempts=self._last_attempts,
                )
        except httpx.HTTPStatusError as exc:
            status = exc.response.status_code
            text = exc.response.text
            logger.error("Gemini API error: %s - %s", status, text)
            if status in (401, 403):
                raise GeminiAuthError(
                    "Invalid Gemini credentials",
                    status_code=status,
                    model_attempts=self._last_attempts,
                ) from exc
            if status == 429:
                raise GeminiRateLimitError(
                    "Gemini quota/rate limit exceeded",
                    status_code=status,
                    model_attempts=self._last_attempts,
                ) from exc
            if status >= 500:
                raise GeminiServerError(
                    "Gemini service unavailable",
                    status_code=status,
                    model_attempts=self._last_attempts,
                ) from exc
            raise GeminiClientError(
                "Unexpected Gemini error",
                status_code=status,
                model_attempts=self._last_attempts,
            ) from exc
        except httpx.RequestError as exc:
            logger.error("Gemini request failed: %s", exc)
            raise GeminiClientError(
                "Failed to reach Gemini",
                retryable=False,
                model_attempts=self._last_attempts,
            ) from exc

    @property
    def resolved_model(self) -> str | None:
        return self._resolved_model

    @property
    def last_attempts(self) -> List[Dict[str, Any]]:
        return list(self._last_attempts)

    def _build_preferred_models(
        self,
        preferred_model: str | None,
        fallback_models: List[str] | None,
    ) -> List[str]:
        candidates: List[str] = []

        if self._resolved_model:
            candidates.append(self._resolved_model)

        candidates.append(preferred_model or "")
        candidates.extend(fallback_models or [])
        candidates.extend(
            [
                self.model,
                *DEFAULT_MODEL_CHAIN,
            ]
        )

        # Keep order, remove duplicates/empties.
        unique: List[str] = []
        for item in candidates:
            normalized = self._normalize_model_name(item)
            if normalized and normalized not in unique:
                unique.append(normalized)
        return unique

    def _normalize_model_name(self, model_name: str | None) -> str:
        if not model_name:
            return ""
        model_name = model_name.strip()
        if model_name.startswith("models/"):
            return model_name.split("models/", 1)[1]
        return model_name

    def _to_gemini_contents(self, messages: List[Dict[str, str]]) -> List[Dict[str, Any]]:
        contents: List[Dict[str, Any]] = []
        for message in messages:
            role = message.get("role", "user")
            text = str(message.get("content", "")).strip()
            if not text:
                continue
            gemini_role = "model" if role == "assistant" else "user"
            contents.append({"role": gemini_role, "parts": [{"text": text}]})
        return contents

    def _build_debug_payload_snapshot(self, payload: Dict[str, Any]) -> str:
        safe_payload: Dict[str, Any] = {
            "generationConfig": payload.get("generationConfig", {}),
            "systemInstruction": self._sanitize_node(payload.get("systemInstruction", {})),
            "contents": self._sanitize_node(payload.get("contents", [])),
        }
        return json.dumps(safe_payload, ensure_ascii=False)

    def _build_debug_response_snapshot(self, payload: Dict[str, Any]) -> str:
        safe_payload = self._sanitize_node(payload)
        return json.dumps(safe_payload, ensure_ascii=False)

    def _sanitize_node(self, node: Any) -> Any:
        if isinstance(node, dict):
            return {str(key): self._sanitize_node(value) for key, value in node.items()}
        if isinstance(node, list):
            return [self._sanitize_node(item) for item in node[:6]]
        if isinstance(node, str):
            return self._sanitize_text(node)
        return node

    def _sanitize_text(self, text: str) -> str:
        redacted = text
        redacted = re.sub(
            r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}",
            "[redacted_email]",
            redacted,
        )
        redacted = re.sub(r"\b\d{11,16}\b", "[redacted_number]", redacted)
        redacted = re.sub(
            r"(?i)(api[_-]?key|token|secret)\s*[:=]\s*[A-Za-z0-9_\-]{6,}",
            r"\1=[redacted]",
            redacted,
        )
        return redacted[:700]


gemini_client = GeminiClient()


async def get_gemini_client() -> GeminiClient:
    return gemini_client
