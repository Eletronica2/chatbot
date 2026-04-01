"""Dependency helpers for services"""
from __future__ import annotations

from typing import Optional

from app.services.ai_service import AIService

_ai_service: Optional[AIService] = None


def set_ai_service(service: AIService) -> None:
    global _ai_service
    _ai_service = service


def get_ai_service() -> AIService:
    if _ai_service is None:  # pragma: no cover - guard clause
        raise RuntimeError("AIService not initialized")
    return _ai_service

