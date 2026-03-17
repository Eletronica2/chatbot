"""Intent detection utilities"""
from __future__ import annotations

import re
from typing import List

from app.domain.message import IntentAnalysis


class IntentService:
    """Lightweight keyword-based intent classifier"""

    def __init__(self):
        self._patterns = {
            "greeting": re.compile(r"\b(oi|ol[aá]|bom dia|boa tarde|boa noite)\b", re.I),
            "status_check": re.compile(r"\b(status|acompanhar|pedido)\b", re.I),
            "handoff": re.compile(r"\b(atendente|humano|suporte|falar com)\b", re.I),
            "faq": re.compile(r"\b(d[uú]vida|inform[aç][aã]o|pergunta)\b", re.I),
        }

    def classify(self, text: str) -> IntentAnalysis:
        normalized = text.strip().lower()
        if not normalized:
            return IntentAnalysis(intent="fallback", confidence=0.0)

        for intent, pattern in self._patterns.items():
            if pattern.search(normalized):
                return IntentAnalysis(intent=intent, confidence=0.7)

        return IntentAnalysis(intent="general_question", confidence=0.3)


intent_service = IntentService()


def get_intent_service() -> IntentService:
    return intent_service
