"""Intent detection utilities."""
from __future__ import annotations

import re
import unicodedata
from typing import Dict, Tuple

from app.domain.message import IntentAnalysis


class IntentService:
    """Keyword-based classifier tailored for WhatsApp support flows."""

    def __init__(self):
        self._patterns: Dict[str, Tuple[re.Pattern[str], float]] = {
            "saudacao": (
                re.compile(r"\b(oi|ola|bom dia|boa tarde|boa noite|e ai)\b", re.I),
                0.9,
            ),
            "horario_atendimento": (
                re.compile(
                    r"\b(horario|funcionamento|abre|fecha|atendimento|que horas)\b",
                    re.I,
                ),
                0.88,
            ),
            "entrega": (
                re.compile(r"\b(entrega|prazo|frete|envio)\b", re.I),
                0.86,
            ),
            "pagamento": (
                re.compile(r"\b(pagamento|pagar|pix|cartao|boleto)\b", re.I),
                0.86,
            ),
            "cardapio": (
                re.compile(r"\b(cardapio|menu|prato|comida)\b", re.I),
                0.83,
            ),
            "agendamento": (
                re.compile(r"\b(agendar|agendamento|marcar horario|consulta)\b", re.I),
                0.84,
            ),
            "atendente": (
                re.compile(r"\b(atendente|humano|suporte|falar com)\b", re.I),
                0.9,
            ),
            "pedido_status": (
                re.compile(r"\b(status|acompanhar|pedido)\b", re.I),
                0.82,
            ),
            "faq": (
                re.compile(r"\b(duvida|informacao|pergunta|faq)\b", re.I),
                0.78,
            ),
        }

    def classify(self, text: str) -> IntentAnalysis:
        normalized = self._normalize_text(text)
        if not normalized:
            return IntentAnalysis(intent="fallback", confidence=0.0)

        for intent, (pattern, confidence) in self._patterns.items():
            if pattern.search(normalized):
                return IntentAnalysis(intent=intent, confidence=confidence)

        return IntentAnalysis(intent="general_question", confidence=0.35)

    def _normalize_text(self, text: str) -> str:
        stripped = (text or "").strip().lower()
        if not stripped:
            return ""
        normalized = unicodedata.normalize("NFKD", stripped)
        return "".join(ch for ch in normalized if not unicodedata.combining(ch))


intent_service = IntentService()


def get_intent_service() -> IntentService:
    return intent_service


