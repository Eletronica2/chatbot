"""Versioned, effective-dated Meta rate cards. Used rates are never edited."""
from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from app.db.mysql import MySQLDatabase
from app.domain.billing_v2 import OPERATIONAL_CATEGORIES, normalize_category

logger = logging.getLogger(__name__)

_COLUMNS = """
    id, provider, version_code, market, currency, category, rate_micros, unit_price,
    billing_basis, free_allowance, allowance_scope, tier_min, tier_max,
    effective_from, effective_to, source_reference, source_checked_at, notes,
    needs_review, active, created_at
"""


@dataclass(frozen=True)
class RateCard:
    id: int
    provider: str
    version_code: str
    market: str
    currency: str
    category: str
    unit_price: Decimal
    billing_basis: str
    free_allowance: int
    allowance_scope: str | None
    tier_min: int
    tier_max: int | None
    effective_from: date
    effective_to: date | None
    needs_review: bool

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "provider": self.provider,
            "version_code": self.version_code,
            "market": self.market,
            "currency": self.currency,
            "category": self.category,
            "unit_price": str(self.unit_price),
            "billing_basis": self.billing_basis,
            "free_allowance": self.free_allowance,
            "allowance_scope": self.allowance_scope,
            "tier_min": self.tier_min,
            "tier_max": self.tier_max,
            "effective_from": str(self.effective_from),
            "effective_to": str(self.effective_to) if self.effective_to else None,
            "needs_review": self.needs_review,
        }


def _row_to_card(row: dict[str, Any]) -> RateCard:
    unit_price = row.get("unit_price")
    if unit_price is None:
        unit_price = Decimal(int(row.get("rate_micros") or 0)) / Decimal(1_000_000)
    return RateCard(
        id=int(row["id"]),
        provider=str(row.get("provider") or "meta"),
        version_code=str(row.get("version_code") or ""),
        market=str(row.get("market") or "BR"),
        currency=str(row.get("currency") or "BRL"),
        category=str(row.get("category") or ""),
        unit_price=Decimal(str(unit_price)),
        billing_basis=str(row.get("billing_basis") or "per_delivered_message"),
        free_allowance=int(row.get("free_allowance") or 0),
        allowance_scope=row.get("allowance_scope"),
        tier_min=int(row.get("tier_min") or 0),
        tier_max=(int(row["tier_max"]) if row.get("tier_max") is not None else None),
        effective_from=row.get("effective_from"),
        effective_to=row.get("effective_to"),
        needs_review=bool(row.get("needs_review")),
    )


def effective_unit_cost(card: RateCard | None, prior_usage_in_scope: int = 0) -> Decimal | None:
    """Unit cost after free allowance (e.g. N free per phone number per period)."""
    if card is None:
        return None
    if card.free_allowance > 0 and prior_usage_in_scope < card.free_allowance:
        return Decimal("0")
    return card.unit_price


class MetaRateEngine:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    def resolve(
        self,
        category: str,
        *,
        market: str = "BR",
        currency: str = "BRL",
        at: date | None = None,
        volume_in_period: int = 0,
        cursor=None,
    ) -> RateCard | None:
        when = at or datetime.utcnow().date()
        params = ("meta", market.upper(), currency.upper(), normalize_category(category), when, when)
        query = f"""
            SELECT {_COLUMNS} FROM meta_rate_cards
            WHERE provider=%s AND market=%s AND currency=%s AND category=%s AND active=1
              AND effective_from <= %s AND (effective_to IS NULL OR effective_to >= %s)
            ORDER BY effective_from DESC, tier_min ASC
        """
        if cursor is not None:
            cursor.execute(query, params)
            rows = list(cursor.fetchall() or [])
        else:
            rows = self.database.fetch_all(query, params)
        if not rows:
            return None
        latest_from = rows[0].get("effective_from")
        same_version = [r for r in rows if r.get("effective_from") == latest_from]
        for row in same_version:
            tier_min = int(row.get("tier_min") or 0)
            tier_max = row.get("tier_max")
            if volume_in_period >= tier_min and (tier_max is None or volume_in_period <= int(tier_max)):
                return _row_to_card(row)
        return _row_to_card(same_version[0])

    def worst_case_operational(self, *, market: str = "BR", at: date | None = None) -> Decimal | None:
        rates = [self.resolve(category, market=market, at=at) for category in sorted(OPERATIONAL_CATEGORIES)]
        known = [card.unit_price for card in rates if card is not None]
        return max(known) if known else None

    def list_cards(self, *, market: str | None = None) -> list[dict[str, Any]]:
        if market:
            rows = self.database.fetch_all(
                f"SELECT {_COLUMNS} FROM meta_rate_cards WHERE market=%s ORDER BY effective_from DESC, category ASC, tier_min ASC",
                (market.upper(),),
            )
        else:
            rows = self.database.fetch_all(
                f"SELECT {_COLUMNS} FROM meta_rate_cards ORDER BY effective_from DESC, category ASC, tier_min ASC"
            )
        used = {
            int(r["rate_id"])
            for r in self.database.fetch_all(
                """
                SELECT DISTINCT meta_rate_card_id AS rate_id FROM billing_reservations
                WHERE meta_rate_card_id IS NOT NULL
                UNION
                SELECT DISTINCT rate_card_id AS rate_id FROM usage_events WHERE rate_card_id IS NOT NULL
                """
            )
        }
        today = datetime.utcnow().date()
        latest_effective: dict[tuple, date] = {}
        for row in rows:
            card = _row_to_card(row)
            if not row.get("active") or card.effective_from > today:
                continue
            if card.effective_to is not None and card.effective_to < today:
                continue
            key = (card.provider, card.market, card.currency, card.category, card.tier_min)
            if key not in latest_effective or card.effective_from > latest_effective[key]:
                latest_effective[key] = card.effective_from
        result: list[dict[str, Any]] = []
        for row in rows:
            card = _row_to_card(row)
            key = (card.provider, card.market, card.currency, card.category, card.tier_min)
            item = card.as_dict()
            item.update(
                {
                    "source_reference": row.get("source_reference"),
                    "source_checked_at": str(row["source_checked_at"]) if row.get("source_checked_at") else None,
                    "notes": row.get("notes"),
                    "active": bool(row.get("active")),
                    "in_use": card.id in used,
                    "current": latest_effective.get(key) == card.effective_from,
                }
            )
            result.append(item)
        return result

    def create_version(self, payload: dict[str, Any]) -> list[dict[str, Any]]:
        """Insert a new effective-dated version. Existing rows are never modified."""
        version_code = str(payload.get("version_code") or "").strip()
        market = str(payload.get("market") or "BR").strip().upper()
        currency = str(payload.get("currency") or "BRL").strip().upper()
        effective_from = payload.get("effective_from")
        rates = payload.get("rates") or []
        if not version_code or not effective_from or not rates:
            raise ValueError("version_code, effective_from e rates são obrigatórios")
        if isinstance(effective_from, str):
            effective_from = date.fromisoformat(effective_from)
        created: list[int] = []
        with self.database.transaction() as conn:
            with conn.cursor() as cursor:
                for rate in rates:
                    category = normalize_category(rate.get("category"))
                    unit_price = Decimal(str(rate.get("unit_price")))
                    if unit_price < 0:
                        raise ValueError("unit_price não pode ser negativo")
                    tier_min = int(rate.get("tier_min") or 0)
                    cursor.execute(
                        """
                        SELECT id FROM meta_rate_cards
                        WHERE provider='meta' AND market=%s AND currency=%s AND category=%s
                          AND effective_from=%s AND tier_min=%s
                        """,
                        (market, currency, category, effective_from, tier_min),
                    )
                    if cursor.fetchone():
                        raise ValueError(
                            f"Já existe rate card {category} em {effective_from}; crie nova vigência em vez de editar"
                        )
                    cursor.execute(
                        """
                        INSERT INTO meta_rate_cards
                            (provider, version_code, market, currency, category, rate_micros, unit_price,
                             billing_basis, free_allowance, allowance_scope, tier_min, tier_max,
                             effective_from, effective_to, source_reference, source_checked_at, notes,
                             needs_review, active)
                        VALUES ('meta', %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 1)
                        """,
                        (
                            version_code,
                            market,
                            currency,
                            category,
                            int((unit_price * 1_000_000).to_integral_value()),
                            unit_price,
                            str(rate.get("billing_basis") or "per_delivered_message"),
                            int(rate.get("free_allowance") or 0),
                            rate.get("allowance_scope"),
                            tier_min,
                            rate.get("tier_max"),
                            effective_from,
                            rate.get("effective_to"),
                            payload.get("source_reference"),
                            payload.get("source_checked_at"),
                            rate.get("notes") or payload.get("notes"),
                            1 if payload.get("needs_review", True) else 0,
                        ),
                    )
                    created.append(int(cursor.lastrowid))
        return [c for c in self.list_cards(market=market) if c["id"] in created]

    def mark_reviewed(self, card_id: int, *, source_checked_at: date, source_reference: str | None) -> bool:
        """Only review metadata changes; price/category/dates stay immutable."""
        changed = self.database.execute(
            """
            UPDATE meta_rate_cards
            SET needs_review=0, source_checked_at=%s,
                source_reference=COALESCE(%s, source_reference)
            WHERE id=%s
            """,
            (source_checked_at, source_reference, card_id),
        )
        return changed > 0
