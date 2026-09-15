"""Usage ledger for delivered WhatsApp messages and Meta rate cards."""
from __future__ import annotations

import asyncio
import csv
import io
import json
import logging
import uuid
from datetime import datetime
from typing import Any

from app.db.mysql import MySQLDatabase

logger = logging.getLogger(__name__)


class UsageLedgerService:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def record_delivered(
        self,
        tenant_id: str,
        provider_message_id: str,
        *,
        category: str | None = None,
        market: str = "BR",
        quantity: int = 1,
        delivered_at: datetime | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Insert a delivered usage event. UNIQUE on (tenant, provider_message_id, event_type).

        Returns created=False when the event already exists (idempotent).
        """
        provider_message_id = (provider_message_id or "").strip()
        if not provider_message_id:
            return {"created": False, "reason": "missing_provider_message_id"}

        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        event_id = str(uuid.uuid4())
        when = delivered_at or datetime.utcnow()
        period = when.strftime("%Y-%m")
        event_type = "delivered"
        meta_json = json.dumps(metadata) if metadata else None

        def _insert() -> dict[str, Any]:
            existing = self.database.fetch_one(
                """
                SELECT id, provider_message_id, category, market, event_type,
                       quantity, delivered_at, billing_period, stripe_status, created_at
                FROM usage_events
                WHERE tenant_id = %s
                  AND provider_message_id = %s
                  AND event_type = %s
                LIMIT 1
                """,
                (tenant_pk, provider_message_id, event_type),
            )
            if existing is not None:
                return {
                    "created": False,
                    "id": str(existing.get("id") or ""),
                    "tenant_id": tenant_id,
                    "provider_message_id": provider_message_id,
                    "event_type": event_type,
                    "billing_period": existing.get("billing_period"),
                }

            try:
                self.database.execute(
                    """
                    INSERT INTO usage_events (
                        id, tenant_id, provider_message_id, direction, category, market,
                        event_type, quantity, delivered_at, billing_period, stripe_status, metadata
                    ) VALUES (%s, %s, %s, 'outgoing', %s, %s, %s, %s, %s, %s, 'pending', %s)
                    """,
                    (
                        event_id,
                        tenant_pk,
                        provider_message_id,
                        category,
                        market or "BR",
                        event_type,
                        max(int(quantity), 1),
                        when,
                        period,
                        meta_json,
                    ),
                )
            except Exception as exc:
                # Race on UNIQUE — treat as duplicate
                if "Duplicate" in str(exc) or "uq_usage_provider_msg" in str(exc):
                    return {
                        "created": False,
                        "id": event_id,
                        "tenant_id": tenant_id,
                        "provider_message_id": provider_message_id,
                        "event_type": event_type,
                        "billing_period": period,
                    }
                raise

            return {
                "created": True,
                "id": event_id,
                "tenant_id": tenant_id,
                "provider_message_id": provider_message_id,
                "event_type": event_type,
                "category": category,
                "market": market or "BR",
                "quantity": max(int(quantity), 1),
                "billing_period": period,
                "delivered_at": when,
                "stripe_status": "pending",
            }

        return await asyncio.to_thread(_insert)

    async def list_period(self, tenant_id: str, period: str) -> list[dict[str, Any]]:
        cleaned = (period or "").strip()
        if len(cleaned) != 7 or cleaned[4] != "-":
            raise ValueError("period must be YYYY-MM")
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _list() -> list[dict[str, Any]]:
            rows = self.database.fetch_all(
                """
                SELECT id, provider_message_id, direction, category, market, event_type,
                       quantity, delivered_at, billing_period, stripe_meter_event_id,
                       stripe_status, metadata, created_at
                FROM usage_events
                WHERE tenant_id = %s AND billing_period = %s
                ORDER BY created_at DESC
                """,
                (tenant_pk, cleaned),
            )
            return [
                {
                    "id": str(row.get("id") or ""),
                    "tenant_id": tenant_id,
                    "provider_message_id": str(row.get("provider_message_id") or ""),
                    "direction": str(row.get("direction") or "outgoing"),
                    "category": row.get("category"),
                    "market": str(row.get("market") or "BR"),
                    "event_type": str(row.get("event_type") or "delivered"),
                    "quantity": int(row.get("quantity") or 1),
                    "delivered_at": row.get("delivered_at"),
                    "billing_period": row.get("billing_period"),
                    "stripe_meter_event_id": row.get("stripe_meter_event_id"),
                    "stripe_status": str(row.get("stripe_status") or "pending"),
                    "metadata": row.get("metadata"),
                    "created_at": row.get("created_at"),
                }
                for row in rows
            ]

        return await asyncio.to_thread(_list)

    async def get_meta_rate_cards(self, market: str = "BR") -> list[dict[str, Any]]:
        market_key = (market or "BR").strip().upper() or "BR"
        today = datetime.utcnow().date()

        def _load() -> list[dict[str, Any]]:
            rows = self.database.fetch_all(
                """
                SELECT id, market, currency, category, rate_micros, effective_from,
                       effective_to, source_reference, notes, updated_at
                FROM meta_rate_cards
                WHERE market = %s
                  AND effective_from <= %s
                  AND (effective_to IS NULL OR effective_to >= %s)
                ORDER BY category ASC, effective_from DESC
                """,
                (market_key, today, today),
            )
            # Keep latest effective card per category
            seen: set[str] = set()
            cards: list[dict[str, Any]] = []
            for row in rows:
                category = str(row.get("category") or "")
                if category in seen:
                    continue
                seen.add(category)
                cards.append(
                    {
                        "id": int(row.get("id") or 0),
                        "market": str(row.get("market") or market_key),
                        "currency": str(row.get("currency") or "BRL"),
                        "category": category,
                        "rate_micros": int(row.get("rate_micros") or 0),
                        "effective_from": row.get("effective_from"),
                        "effective_to": row.get("effective_to"),
                        "source_reference": row.get("source_reference"),
                        "notes": row.get("notes"),
                        "updated_at": row.get("updated_at"),
                    }
                )
            return cards

        return await asyncio.to_thread(_load)

    def export_csv(self, events: list[dict[str, Any]]) -> str:
        buffer = io.StringIO()
        writer = csv.DictWriter(
            buffer,
            fieldnames=[
                "id",
                "tenant_id",
                "provider_message_id",
                "category",
                "market",
                "event_type",
                "quantity",
                "billing_period",
                "stripe_status",
                "delivered_at",
            ],
            extrasaction="ignore",
        )
        writer.writeheader()
        for event in events:
            row = dict(event)
            for key in ("delivered_at", "created_at"):
                if key in row and row[key] is not None and not isinstance(row[key], str):
                    row[key] = str(row[key])
            writer.writerow(row)
        return buffer.getvalue()

    async def mark_stripe_status(
        self,
        tenant_id: str,
        provider_message_id: str,
        *,
        status: str,
        meter_event_id: str | None = None,
        event_type: str = "delivered",
    ) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _update() -> None:
            self.database.execute(
                """
                UPDATE usage_events
                SET stripe_status = %s,
                    stripe_meter_event_id = COALESCE(%s, stripe_meter_event_id)
                WHERE tenant_id = %s
                  AND provider_message_id = %s
                  AND event_type = %s
                """,
                (status, meter_event_id, tenant_pk, provider_message_id, event_type),
            )

        await asyncio.to_thread(_update)
