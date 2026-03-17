"""Wrapper around OpenAI Chat Completions"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

import httpx

from app.config.settings import settings

logger = logging.getLogger(__name__)


class OpenAIClientError(Exception):
    """Base error for OpenAI client issues"""

    def __init__(self, message: str, status_code: Optional[int] = None, retryable: bool = False):
        super().__init__(message)
        self.status_code = status_code
        self.retryable = retryable


class OpenAIAuthError(OpenAIClientError):
    pass


class OpenAIRateLimitError(OpenAIClientError):
    pass


class OpenAIServerError(OpenAIClientError):
    pass


class OpenAIClient:
    """Simple HTTP client for OpenAI chat completions"""

    def __init__(self, api_key: str | None = None, model: str | None = None):
        self.api_key = api_key or settings.OPENAI_API_KEY
        self.model = model or settings.OPENAI_MODEL
        self.timeout = settings.OPENAI_TIMEOUT
        self.base_url = "https://api.openai.com/v1/chat/completions"

    async def create_chat_completion(self, messages: List[Dict[str, str]]) -> Dict[str, Any]:
        if not self.api_key:
            raise OpenAIAuthError("Missing OPENAI_API_KEY")
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        payload = {
            "model": self.model,
            "messages": messages,
            "temperature": 0.5,
            "max_tokens": 400,
        }
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(self.base_url, headers=headers, json=payload)
                response.raise_for_status()
                return response.json()
        except httpx.HTTPStatusError as exc:  # pragma: no cover - network failure guard
            status = exc.response.status_code
            text = exc.response.text
            logger.error("OpenAI API error: %s - %s", status, text)
            if status == 401:
                raise OpenAIAuthError("Invalid OpenAI credentials", status_code=status) from exc
            if status == 429:
                raise OpenAIRateLimitError("OpenAI rate limit or quota exceeded", status_code=status) from exc
            if status >= 500:
                raise OpenAIServerError("OpenAI service unavailable", status_code=status, retryable=False) from exc
            raise OpenAIClientError("Unexpected OpenAI error", status_code=status) from exc
        except httpx.RequestError as exc:  # pragma: no cover - network failure guard
            logger.error("OpenAI request failed: %s", exc)
            raise OpenAIClientError("Failed to reach OpenAI", retryable=False) from exc


openai_client = OpenAIClient()


async def get_openai_client() -> OpenAIClient:
    return openai_client
