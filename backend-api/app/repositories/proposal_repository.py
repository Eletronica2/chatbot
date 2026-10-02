"""Repository for commercial proposals."""
from __future__ import annotations

import asyncio
import json
from decimal import Decimal
from typing import Any

from app.db.mysql import MySQLDatabase


_ALLOWED_STATUSES = {"draft", "sent", "accepted", "rejected"}

_SELECT_COLUMNS = """
    p.id, p.lead_id, p.tenant_id, p.company_name, p.contact_name, p.contact_email,
    p.contact_whatsapp, p.plan, p.catalog_version, p.plan_code, p.billing_mode,
    p.monthly_value, p.setup_fee, p.monthly_message_limit, p.operational_volume,
    p.marketing_volume, p.marketing_estimate, p.included_items, p.pricing_snapshot,
    p.margin_snapshot, p.margin_override_reason, p.margin_override_by,
    p.validity_days, p.status, p.notes, p.created_by_user_id, p.created_at, p.updated_at
"""


def _normalize_items(items: list[str] | None) -> str | None:
    if not items:
        return None
    clean = [str(item).strip() for item in items if str(item).strip()]
    if not clean:
        return None
    return json.dumps(clean, ensure_ascii=False)


def _json_or_none(value: dict[str, Any] | None) -> str | None:
    if value is None:
        return None
    return json.dumps(value, ensure_ascii=False, default=str)


def _to_decimal(value: Any) -> Decimal:
    if value is None:
        return Decimal("0")
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))


class ProposalRepository:
    def __init__(self, database: MySQLDatabase) -> None:
        self.database = database

    async def create(
        self,
        *,
        lead_id: int | None,
        tenant_id: int | None,
        company_name: str,
        contact_name: str,
        contact_email: str,
        contact_whatsapp: str | None,
        plan: str,
        monthly_value: Decimal,
        setup_fee: Decimal,
        monthly_message_limit: int,
        included_items: list[str] | None,
        validity_days: int,
        status: str,
        notes: str | None,
        created_by_user_id: int | None,
        catalog_version: str | None = None,
        plan_code: str | None = None,
        billing_mode: str | None = None,
        operational_volume: int | None = None,
        marketing_volume: int | None = None,
        marketing_estimate: Decimal | None = None,
        pricing_snapshot: dict[str, Any] | None = None,
        margin_snapshot: dict[str, Any] | None = None,
        margin_override_reason: str | None = None,
        margin_override_by: str | None = None,
    ) -> dict[str, Any] | None:
        items_json = _normalize_items(included_items)

        def _insert() -> dict[str, Any] | None:
            proposal_id = self.database.insert(
                """
                INSERT INTO proposals (
                    lead_id, tenant_id, company_name, contact_name, contact_email, contact_whatsapp,
                    plan, catalog_version, plan_code, billing_mode, monthly_value, setup_fee,
                    monthly_message_limit, operational_volume, marketing_volume, marketing_estimate,
                    included_items, pricing_snapshot, margin_snapshot, margin_override_reason,
                    margin_override_by, validity_days, status, notes, created_by_user_id
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    lead_id,
                    tenant_id,
                    company_name,
                    contact_name,
                    contact_email,
                    contact_whatsapp,
                    plan,
                    catalog_version,
                    plan_code,
                    billing_mode,
                    str(monthly_value),
                    str(setup_fee),
                    int(monthly_message_limit),
                    operational_volume,
                    marketing_volume,
                    str(marketing_estimate) if marketing_estimate is not None else None,
                    items_json,
                    _json_or_none(pricing_snapshot),
                    _json_or_none(margin_snapshot),
                    margin_override_reason,
                    margin_override_by,
                    int(validity_days),
                    status,
                    notes,
                    int(created_by_user_id) if created_by_user_id is not None else None,
                ),
            )
            return self._get_by_id(proposal_id)

        return await asyncio.to_thread(_insert)

    async def list_all(
        self,
        *,
        lead_id: int | None = None,
        status: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict[str, Any]]:
        clauses: list[str] = []
        params: list[Any] = []
        if lead_id is not None:
            clauses.append("p.lead_id = %s")
            params.append(int(lead_id))
        if status and status in _ALLOWED_STATUSES:
            clauses.append("p.status = %s")
            params.append(status)
        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        params.extend([int(limit), int(offset)])

        def _query() -> list[dict[str, Any]]:
            return self.database.fetch_all(
                f"""
                SELECT {_SELECT_COLUMNS}
                FROM proposals p
                {where}
                ORDER BY p.created_at DESC, p.id DESC
                LIMIT %s OFFSET %s
                """,
                tuple(params),
            )

        return await asyncio.to_thread(_query)

    async def get_by_id(self, proposal_id: int) -> dict[str, Any] | None:
        return await asyncio.to_thread(self._get_by_id, proposal_id)

    async def update_proposal(
        self,
        *,
        proposal_id: int,
        status: str | None = None,
        notes: str | None = None,
        monthly_value: Decimal | None = None,
        setup_fee: Decimal | None = None,
        monthly_message_limit: int | None = None,
        included_items: list[str] | None = None,
        validity_days: int | None = None,
        plan: str | None = None,
        margin_snapshot: dict[str, Any] | None = None,
        margin_override_reason: str | None = None,
        margin_override_by: str | None = None,
    ) -> dict[str, Any] | None:
        def _update() -> dict[str, Any] | None:
            clauses: list[str] = []
            params: list[Any] = []
            if status is not None:
                if status not in _ALLOWED_STATUSES:
                    raise ValueError(f"Status invalido: {status}")
                clauses.append("status = %s")
                params.append(status)
            if notes is not None:
                clauses.append("notes = %s")
                params.append(notes)
            if monthly_value is not None:
                clauses.append("monthly_value = %s")
                params.append(str(monthly_value))
            if setup_fee is not None:
                clauses.append("setup_fee = %s")
                params.append(str(setup_fee))
            if monthly_message_limit is not None:
                clauses.append("monthly_message_limit = %s")
                params.append(int(monthly_message_limit))
            if included_items is not None:
                clauses.append("included_items = %s")
                params.append(_normalize_items(included_items))
            if validity_days is not None:
                clauses.append("validity_days = %s")
                params.append(int(validity_days))
            if plan is not None:
                clauses.append("plan = %s")
                params.append(plan)
            if margin_snapshot is not None:
                clauses.append("margin_snapshot = %s")
                params.append(_json_or_none(margin_snapshot))
            if margin_override_reason is not None:
                clauses.append("margin_override_reason = %s")
                params.append(margin_override_reason)
                clauses.append("margin_override_by = %s")
                params.append(margin_override_by)
            if not clauses:
                return self._get_by_id(proposal_id)
            params.append(int(proposal_id))
            self.database.execute(
                f"UPDATE proposals SET {', '.join(clauses)}, updated_at = CURRENT_TIMESTAMP WHERE id = %s",
                tuple(params),
            )
            return self._get_by_id(proposal_id)

        return await asyncio.to_thread(_update)

    def _get_by_id(self, proposal_id: int) -> dict[str, Any] | None:
        return self.database.fetch_one(
            f"""
            SELECT {_SELECT_COLUMNS}
            FROM proposals p
            WHERE p.id = %s
            LIMIT 1
            """,
            (int(proposal_id),),
        )
