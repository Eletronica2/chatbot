"""Versioned commercial catalog (plans, top-ups, campaign credits) and cost config."""
from __future__ import annotations

import json
from decimal import Decimal
from typing import Any

from app.db.mysql import MySQLDatabase
from app.domain.billing_v2 import (
    CatalogPlan,
    CostInputs,
    VolumeAnswer,
    marketing_packs,
    suggest_plan,
    PlanSuggestion,
)


def _dec(value: Any) -> Decimal | None:
    if value is None:
        return None
    return Decimal(str(value))


class BillingCatalogService:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    def list_items(self, *, include_legacy: bool = False) -> list[dict[str, Any]]:
        where = "" if include_legacy else "WHERE status='active'"
        rows = self.database.fetch_all(
            f"""
            SELECT code, catalog_version, kind, plan_key, label, price, currency,
                   operational_units, marketing_units, is_custom, status, sort_order, metadata
            FROM billing_catalog_items {where}
            ORDER BY sort_order ASC, id ASC
            """
        )
        return [self._serialize(row) for row in rows]

    def get_item(self, code: str, *, cursor=None) -> dict[str, Any] | None:
        query = """
            SELECT code, catalog_version, kind, plan_key, label, price, currency,
                   operational_units, marketing_units, is_custom, status, sort_order, metadata
            FROM billing_catalog_items WHERE code=%s
        """
        if cursor is not None:
            cursor.execute(query, (code,))
            row = cursor.fetchone()
        else:
            row = self.database.fetch_one(query, (code,))
        return self._serialize(row) if row else None

    def active_plans(self) -> list[CatalogPlan]:
        return [
            CatalogPlan(
                code=item["code"],
                plan_key=item["plan_key"] or "",
                label=item["label"],
                price=_dec(item["price"]),
                operational_units=item["operational_units"],
                is_custom=item["is_custom"],
                catalog_version=item["catalog_version"],
            )
            for item in self.list_items()
            if item["kind"] == "plan"
        ]

    def suggest(self, operational: VolumeAnswer) -> PlanSuggestion:
        return suggest_plan(self.active_plans(), operational)

    def marketing_unit_item(self) -> dict[str, Any] | None:
        return next((i for i in self.list_items() if i["kind"] == "marketing_unit"), None)

    def marketing_unit_price(self) -> Decimal | None:
        item = self.marketing_unit_item()
        return _dec(item["price"]) if item else None

    def marketing_pack_offers(self) -> list[dict[str, Any]]:
        item = self.marketing_unit_item()
        if not item or item["price"] is None:
            return []
        sizes = (item.get("metadata") or {}).get("pack_sizes") or [100, 500, 1000, 5000]
        return [
            {"units": p["units"], "price": str(p["price"]), "catalog_item_code": item["code"]}
            for p in marketing_packs(Decimal(item["price"]), sizes)
        ]

    def topup_offers(self) -> list[dict[str, Any]]:
        return [i for i in self.list_items() if i["kind"] == "topup_operational"]

    # ---------------------------------------------------------------- costs
    def cost_config(self) -> dict[str, Decimal | None]:
        rows = self.database.fetch_all("SELECT config_key, value FROM billing_cost_config")
        return {str(r["config_key"]): _dec(r.get("value")) for r in rows}

    def cost_config_rows(self) -> list[dict[str, Any]]:
        rows = self.database.fetch_all(
            "SELECT config_key, value, description, updated_by_user_id, updated_at FROM billing_cost_config ORDER BY config_key"
        )
        return [
            {
                "key": r["config_key"],
                "value": str(r["value"]) if r.get("value") is not None else None,
                "description": r.get("description"),
                "updated_by_user_id": r.get("updated_by_user_id"),
                "updated_at": r.get("updated_at"),
            }
            for r in rows
        ]

    def update_cost_config(self, key: str, value: Decimal | None, *, actor_id: str | None) -> dict[str, Any]:
        existing = self.database.fetch_one(
            "SELECT config_key, value FROM billing_cost_config WHERE config_key=%s", (key,)
        )
        if existing is None:
            raise ValueError("Chave de custo desconhecida")
        if value is not None and value < 0:
            raise ValueError("Valor não pode ser negativo")
        self.database.execute(
            "UPDATE billing_cost_config SET value=%s, updated_by_user_id=%s WHERE config_key=%s",
            (value, actor_id, key),
        )
        return {
            "key": key,
            "old_value": str(existing["value"]) if existing.get("value") is not None else None,
            "new_value": str(value) if value is not None else None,
        }

    def cost_inputs(self) -> CostInputs:
        cfg = self.cost_config()
        return CostInputs(
            target_margin=cfg.get("target_margin") or Decimal("0.30"),
            payment_fee_percent=cfg.get("payment_fee_percent"),
            payment_fee_fixed=cfg.get("payment_fee_fixed"),
            tax_rate=cfg.get("tax_rate"),
            ai_cost_per_operational_message=cfg.get("ai_cost_per_operational_message"),
            allocated_platform_cost=cfg.get("allocated_platform_cost_per_tenant"),
        )

    @staticmethod
    def _serialize(row: dict[str, Any]) -> dict[str, Any]:
        metadata = row.get("metadata")
        if isinstance(metadata, (str, bytes)):
            try:
                metadata = json.loads(metadata)
            except ValueError:
                metadata = None
        price = row.get("price")
        return {
            "code": row["code"],
            "catalog_version": row["catalog_version"],
            "kind": row["kind"],
            "plan_key": row.get("plan_key"),
            "label": row["label"],
            "price": str(Decimal(str(price)).quantize(Decimal("0.01"))) if price is not None else None,
            "currency": row.get("currency") or "BRL",
            "operational_units": int(row["operational_units"]) if row.get("operational_units") is not None else None,
            "marketing_units": int(row["marketing_units"]) if row.get("marketing_units") is not None else None,
            "is_custom": bool(row.get("is_custom")),
            "status": row.get("status") or "active",
            "metadata": metadata or {},
        }
