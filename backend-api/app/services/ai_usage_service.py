"""AI token usage per tenant/conversation. Cost is UNKNOWN (NULL) without a rate card."""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime
from decimal import Decimal
from typing import Any

from app.db.mysql import MySQLDatabase

logger = logging.getLogger(__name__)


def _int_or_none(value: Any) -> int | None:
    try:
        return int(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def extract_usage(metadata: dict[str, Any] | None) -> dict[str, Any] | None:
    usage = (metadata or {}).get("ai_usage")
    if not isinstance(usage, dict):
        return None
    return {
        "provider": str(usage.get("provider") or "gemini")[:32],
        "model": (str(usage.get("model")) if usage.get("model") else None),
        "input_tokens": _int_or_none(usage.get("input_tokens")),
        "output_tokens": _int_or_none(usage.get("output_tokens")),
        "cached_tokens": _int_or_none(usage.get("cached_tokens")),
    }


def estimate_cost(rate: dict[str, Any] | None, usage: dict[str, Any]) -> Decimal | None:
    if not rate or usage.get("input_tokens") is None or usage.get("output_tokens") is None:
        return None
    million = Decimal(1_000_000)
    cached = Decimal(usage.get("cached_tokens") or 0)
    billable_input = Decimal(usage["input_tokens"]) - cached
    cost = billable_input * Decimal(str(rate["input_per_million"])) / million
    cost += Decimal(usage["output_tokens"]) * Decimal(str(rate["output_per_million"])) / million
    cached_rate = rate.get("cached_input_per_million")
    cost += cached * Decimal(str(cached_rate if cached_rate is not None else rate["input_per_million"])) / million
    return cost.quantize(Decimal("0.000001"))


class AIUsageService:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    def _rate(self, provider: str, model: str | None) -> dict[str, Any] | None:
        if not model:
            return None
        return self.database.fetch_one(
            """
            SELECT id, currency, input_per_million, output_per_million, cached_input_per_million
            FROM ai_rate_cards
            WHERE provider=%s AND model=%s AND active=1 AND effective_from <= %s
              AND (effective_to IS NULL OR effective_to >= %s)
            ORDER BY effective_from DESC LIMIT 1
            """,
            (provider, model, datetime.utcnow().date(), datetime.utcnow().date()),
        )

    def record_sync(self, tenant_key: str, metadata: dict[str, Any] | None, *, session_id: str | None, inbound_message_id: str | None) -> bool:
        usage = extract_usage(metadata)
        if usage is None:
            return False
        row = self.database.fetch_one("SELECT id FROM tenants WHERE external_key=%s", (tenant_key,))
        if not row:
            return False
        rate = self._rate(usage["provider"], usage["model"])
        cost = estimate_cost(rate, usage)
        self.database.execute(
            """
            INSERT INTO ai_usage_events
                (tenant_id, session_id, inbound_message_id, provider, model, input_tokens, output_tokens,
                 cached_tokens, ai_rate_card_id, estimated_cost, cost_currency)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                int(row["id"]), session_id, inbound_message_id, usage["provider"], usage["model"],
                usage["input_tokens"], usage["output_tokens"], usage["cached_tokens"],
                rate["id"] if rate else None, cost, rate["currency"] if rate else None,
            ),
        )
        return True

    async def record(self, tenant_key: str, metadata: dict[str, Any] | None, *, session_id: str | None = None, inbound_message_id: str | None = None) -> None:
        try:
            await asyncio.to_thread(self.record_sync, tenant_key, metadata, session_id=session_id, inbound_message_id=inbound_message_id)
        except Exception:
            logger.exception("ai_usage_record_failed tenant=%s", tenant_key)
