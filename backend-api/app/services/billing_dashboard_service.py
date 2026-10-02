"""Superadmin billing dashboard: revenue, usage, Meta/AI/payment costs and contribution."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any

from app.db.mysql import MySQLDatabase
from app.domain.billing_v2 import STATUS_LABELS, BillingMode, CostInputs
from app.services.billing_catalog_service import BillingCatalogService
from app.services.billing_gate import BillingGate

_MONEY = Decimal("0.01")


def _d(value: Any) -> Decimal:
    return Decimal(str(value)) if value is not None else Decimal("0")


def _m(value: Decimal | None) -> str | None:
    return str(value.quantize(_MONEY)) if value is not None else None


def contribution_status(revenue: Decimal, known_costs: Decimal, unknown: list[str], target: Decimal) -> tuple[str, Decimal | None]:
    if revenue <= 0:
        return ("partial" if unknown or known_costs == 0 else "red"), None
    margin = (revenue - known_costs) / revenue
    if margin < 0:
        return "red", margin
    if margin < target:
        return "yellow", margin
    if unknown:
        return "partial", margin
    return "green", margin


class BillingDashboardService:
    def __init__(self, database: MySQLDatabase, gate: BillingGate, catalog: BillingCatalogService):
        self.database = database
        self.gate = gate
        self.catalog = catalog

    def tenant_dashboard(self, tenant_key: str, *, period_start: datetime | None = None) -> dict[str, Any]:
        tenant_pk = self.gate.tenant_pk(tenant_key)
        summary = self.gate.summary(tenant_key)
        start = period_start or datetime.utcnow().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        config = self.gate.get_config(tenant_pk)
        costs_cfg: CostInputs = self.catalog.cost_inputs()

        msg = self.database.fetch_one(
            """
            SELECT SUM(direction='incoming') AS inbound, SUM(direction='outgoing') AS outbound
            FROM messages WHERE tenant_id=%s AND created_at >= %s
            """,
            (tenant_pk, start),
        ) or {}
        status_counts = {
            r["status"]: int(r["total"] or 0)
            for r in self.database.fetch_all(
                """
                SELECT status, COUNT(*) AS total FROM billing_reservations
                WHERE tenant_id=%s AND created_at >= %s GROUP BY status
                """,
                (tenant_pk, start),
            )
        }
        by_category = [
            {"category": r["category"], "delivered": int(r["delivered"] or 0), "failed": int(r["failed"] or 0), "pending": int(r["pending"] or 0)}
            for r in self.database.fetch_all(
                """
                SELECT category,
                       SUM(status='committed') AS delivered,
                       SUM(status='released') AS failed,
                       SUM(status IN ('reserved','accepted','pending_reconciliation')) AS pending
                FROM billing_reservations WHERE tenant_id=%s AND created_at >= %s
                GROUP BY category
                """,
                (tenant_pk, start),
            )
        ]
        meta = self.database.fetch_one(
            """
            SELECT
                SUM(CASE WHEN billing_mode=%s THEN meta_cost ELSE 0 END) AS partner_cost,
                SUM(CASE WHEN billing_mode=%s THEN meta_cost ELSE 0 END) AS customer_cost,
                SUM(meta_cost IS NULL AND billing_mode=%s) AS partner_unknown
            FROM usage_events
            WHERE tenant_id=%s AND event_type='delivered' AND created_at >= %s AND reservation_id IS NOT NULL
            """,
            (BillingMode.SOLUTION_PARTNER.value, BillingMode.CUSTOMER_DIRECT.value, BillingMode.SOLUTION_PARTNER.value, tenant_pk, start),
        ) or {}
        ai = self.database.fetch_one(
            """
            SELECT COUNT(*) AS calls, SUM(estimated_cost) AS cost, SUM(estimated_cost IS NULL) AS unknown_calls,
                   SUM(input_tokens) AS input_tokens, SUM(output_tokens) AS output_tokens
            FROM ai_usage_events WHERE tenant_id=%s AND created_at >= %s
            """,
            (tenant_pk, start),
        ) or {}
        topups = self.database.fetch_one(
            """
            SELECT COUNT(*) AS charges, SUM(total_amount) AS revenue,
                   SUM(CASE WHEN unit_type='marketing' THEN total_amount ELSE 0 END) AS marketing_revenue
            FROM billing_topup_purchases
            WHERE tenant_id=%s AND status='granted' AND granted_at >= %s
            """,
            (tenant_pk, start),
        ) or {}

        plan_revenue = _d(config.get("monthly_price")) if config.get("monthly_price") is not None else Decimal("0")
        topup_revenue = _d(topups.get("revenue"))
        revenue = plan_revenue + topup_revenue
        charges = (1 if plan_revenue > 0 else 0) + int(topups.get("charges") or 0)

        unknown: list[str] = []
        meta_cost = _d(meta.get("partner_cost"))
        if int(meta.get("partner_unknown") or 0) > 0:
            unknown.append("meta")
        ai_calls = int(ai.get("calls") or 0)
        ai_cost: Decimal | None = _d(ai.get("cost"))
        if ai_calls and int(ai.get("unknown_calls") or 0) > 0:
            unknown.append("ai")
            ai_cost = _d(ai.get("cost")) if ai.get("cost") is not None else None
        if costs_cfg.payment_fee_percent is None and costs_cfg.payment_fee_fixed is None:
            payment_cost = None
            unknown.append("payment")
        else:
            payment_cost = revenue * (costs_cfg.payment_fee_percent or Decimal(0)) + (costs_cfg.payment_fee_fixed or Decimal(0)) * charges
        if costs_cfg.tax_rate is None:
            tax_cost = None
            unknown.append("tax")
        else:
            tax_cost = revenue * costs_cfg.tax_rate
        allocated = costs_cfg.allocated_platform_cost
        known = meta_cost + (ai_cost or 0) + (payment_cost or 0) + (tax_cost or 0) + (allocated or 0)
        status, margin = contribution_status(revenue, known, unknown, costs_cfg.target_margin)

        return {
            "tenant_id": tenant_key,
            "period_start": start,
            "summary": summary,
            "revenue": {"plan": _m(plan_revenue), "topups": _m(topup_revenue), "marketing_credits": _m(_d(topups.get("marketing_revenue"))), "total": _m(revenue)},
            "messages": {
                "inbound": int(msg.get("inbound") or 0),
                "outbound": int(msg.get("outbound") or 0),
                "delivered": status_counts.get("committed", 0),
                "failed": status_counts.get("released", 0),
                "pending": status_counts.get("reserved", 0) + status_counts.get("accepted", 0),
                "pending_reconciliation": status_counts.get("pending_reconciliation", 0),
            },
            "by_category": by_category,
            "costs": {
                "meta_atende": _m(meta_cost),
                "meta_customer_estimate": _m(_d(meta.get("customer_cost"))),
                "ai": _m(ai_cost),
                "ai_calls": ai_calls,
                "ai_tokens": {"input": int(ai.get("input_tokens") or 0), "output": int(ai.get("output_tokens") or 0)},
                "payment": _m(payment_cost),
                "tax": _m(tax_cost),
                "allocated_platform": _m(allocated),
                "known_total": _m(known),
            },
            "contribution": _m(revenue - known),
            "margin_percent": str((margin * 100).quantize(_MONEY)) if margin is not None else None,
            "status": status,
            "status_label": STATUS_LABELS.get(status, status),
            "unknown_components": unknown,
        }

    def overview(self) -> list[dict[str, Any]]:
        tenants = self.database.fetch_all("SELECT external_key, name FROM tenants ORDER BY name ASC")
        rows: list[dict[str, Any]] = []
        for tenant in tenants:
            try:
                data = self.tenant_dashboard(str(tenant["external_key"]))
            except Exception as exc:  # noqa: BLE001 — one broken tenant must not hide the rest
                rows.append({"tenant_id": tenant["external_key"], "name": tenant["name"], "error": str(exc)[:200]})
                continue
            summary = data["summary"]
            rows.append(
                {
                    "tenant_id": tenant["external_key"],
                    "name": tenant["name"],
                    "billing_mode": summary["billing_mode"],
                    "plan": (summary.get("plan") or {}).get("label"),
                    "is_v2_plan": summary["is_v2_plan"],
                    "operational": summary["operational"],
                    "marketing": {k: summary["marketing"][k] for k in ("available", "reserved", "consumed")},
                    "revenue": data["revenue"]["total"],
                    "contribution": data["contribution"],
                    "margin_percent": data["margin_percent"],
                    "status": data["status"],
                    "status_label": data["status_label"],
                    "messages": data["messages"],
                }
            )
        return rows
