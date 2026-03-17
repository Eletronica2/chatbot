"""Wrapper around Google Gemini generateContent API"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

import httpx

from app.config.settings import settings

logger = logging.getLogger(__name__)


class GeminiClientError(Exception):
    """Base error for Gemini client issues"""

    def __init__(self, message: str, status_code: Optional[int] = None, retryable: bool = False):
        super().__init__(message)
        self.status_code = status_code
        self.retryable = retryable


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

    async def generate_content(self, system_prompt: str, messages: List[Dict[str, str]]) -> Dict[str, Any]:
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

        preferred_models = self._build_preferred_models()

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                for idx, candidate_model in enumerate(preferred_models):
                    try:
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
                        return response.json()
                    except httpx.HTTPStatusError as exc:
                        status = exc.response.status_code
                        text = exc.response.text

                        if status in (404, 429) and idx < len(preferred_models) - 1:
                            logger.warning(
                                "Gemini model '%s' returned status %s, trying next candidate",
                                candidate_model,
                                status
                            )
                            continue

                        logger.error("Gemini API error: %s - %s", status, text)
                        if status in (401, 403):
                            raise GeminiAuthError("Invalid Gemini credentials", status_code=status) from exc
                        if status == 429:
                            raise GeminiRateLimitError("Gemini quota/rate limit exceeded", status_code=status) from exc
                        if status >= 500:
                            raise GeminiServerError("Gemini service unavailable", status_code=status) from exc
                        raise GeminiClientError("Unexpected Gemini error", status_code=status) from exc

                raise GeminiClientError("No compatible Gemini model found", status_code=404)
        except httpx.HTTPStatusError as exc:
            status = exc.response.status_code
            text = exc.response.text
            logger.error("Gemini API error: %s - %s", status, text)
            if status in (401, 403):
                raise GeminiAuthError("Invalid Gemini credentials", status_code=status) from exc
            if status == 429:
                raise GeminiRateLimitError("Gemini quota/rate limit exceeded", status_code=status) from exc
            if status >= 500:
                raise GeminiServerError("Gemini service unavailable", status_code=status) from exc
            raise GeminiClientError("Unexpected Gemini error", status_code=status) from exc
        except httpx.RequestError as exc:
            logger.error("Gemini request failed: %s", exc)
            raise GeminiClientError("Failed to reach Gemini", retryable=False) from exc

    def _build_preferred_models(self) -> List[str]:
        candidates: List[str] = []

        if self._resolved_model:
            candidates.append(self._resolved_model)

        candidates.extend(
            [
                self.model,
                "gemini-2.0-flash",
                "gemini-2.5-flash",
                "gemini-1.5-flash",
                "gemini-1.5-pro",
                "gemini-pro"
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


gemini_client = GeminiClient()


async def get_gemini_client() -> GeminiClient:
    return gemini_client
