"""BillingGate: single entry point for every outbound WhatsApp message.

Lifecycle per message: RESERVE (before send) → ACCEPTED (Meta returned wamid)
→ COMMIT on delivered/read, RELEASE on failed. Inbound never consumes.
All balance changes happen inside one DB transaction with row locks on the
tenant's buckets, and every write is idempotent (unique keys).
"""
from __future__ import annotations

import calendar
import json
import logging
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any, Callable

import pymysql

from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.domain.billing_v2 import (
    CONSUMING_STATUSES,
    MSG_MARKETING_INSUFFICIENT,
    MSG_META_DIRECT,
    MSG_OPERATIONAL_EXHAUSTED,
    BillingMode,
    Entitlement,
    LedgerEntryType,
    ReservationStatus,
    UnitType,
    normalize_category,
    normalize_mode,
    unit_type_for,
    usage_level,
)
from app.services.billing_catalog_service import BillingCatalogService
from app.services.meta_rate_engine import MetaRateEngine, effective_unit_cost

logger = logging.getLogger(__name__)


def log_billing_event(event: str, **fields: Any) -> None:
    """Sanitized key=value event log; never pass message content or credentials."""
    logger.info("%s %s", event, " ".join(f"{k}={v}" for k, v in fields.items() if v is not None))

_OPEN_STATUSES = (
    ReservationStatus.RESERVED.value,
    ReservationStatus.ACCEPTED.value,
    ReservationStatus.PENDING_RECONCILIATION.value,
)
_PAID_SUBSCRIPTION_STATUSES = {"active", "trialing"}
_DEADLOCK_CODES = {1213, 1205}


class TenantNotFound(LookupError):
    pass


@dataclass
class GateDecision:
    allowed: bool
    code: str
    message: str | None = None
    reservation_id: str | None = None
    entitlement: str | None = None
    billing_mode: str | None = None
    category: str | None = None
    unit_type: str | None = None
    meta_unit_cost: Decimal | None = None
    duplicate: bool = False
    level: str | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "allowed": self.allowed,
            "code": self.code,
            "message": self.message,
            "reservation_id": self.reservation_id,
            "entitlement": self.entitlement,
            "billing_mode": self.billing_mode,
            "category": self.category,
            "unit_type": self.unit_type,
            "meta_unit_cost": str(self.meta_unit_cost) if self.meta_unit_cost is not None else None,
            "duplicate": self.duplicate,
            "level": self.level,
        }


def add_months(anchor: datetime, months: int) -> datetime:
    month_index = anchor.month - 1 + months
    year = anchor.year + month_index // 12
    month = month_index % 12 + 1
    day = min(anchor.day, calendar.monthrange(year, month)[1])
    return anchor.replace(year=year, month=month, day=day)


def cycle_bounds(anchor: datetime, now: datetime) -> tuple[datetime, datetime]:
    if now < anchor:
        return anchor, add_months(anchor, 1)
    months = (now.year - anchor.year) * 12 + (now.month - anchor.month)
    start = add_months(anchor, months)
    if start > now:
        months -= 1
        start = add_months(anchor, months)
    return start, add_months(anchor, months + 1)


class BillingGate:
    def __init__(
        self,
        database: MySQLDatabase,
        rate_engine: MetaRateEngine,
        catalog: BillingCatalogService,
        *,
        clock: Callable[[], datetime] | None = None,
    ):
        self.database = database
        self.rate_engine = rate_engine
        self.catalog = catalog
        self._clock = clock or datetime.utcnow
        self._granted_cycles: dict[int, datetime] = {}

    # ------------------------------------------------------------ config
    @property
    def enabled(self) -> bool:
        return bool(settings.BILLING_V2_ENABLED)

    def default_mode(self) -> str:
        return normalize_mode(settings.META_BILLING_DEFAULT)

    def tenant_pk(self, tenant_key: str) -> int:
        row = self.database.fetch_one("SELECT id FROM tenants WHERE external_key=%s", (tenant_key,))
        if not row:
            raise TenantNotFound(tenant_key)
        return int(row["id"])

    def get_config(self, tenant_pk: int, cursor=None) -> dict[str, Any]:
        query = """
            SELECT tenant_id, billing_mode, catalog_version, plan_code, operational_allowance,
                   monthly_price, campaign_policy, billing_v2_active_from, updated_by_user_id, updated_at
            FROM tenant_billing_config WHERE tenant_id=%s
        """
        if cursor is not None:
            cursor.execute(query, (tenant_pk,))
            row = cursor.fetchone()
        else:
            row = self.database.fetch_one(query, (tenant_pk,))
        row = dict(row or {})
        row["effective_mode"] = normalize_mode(row.get("billing_mode"), self.default_mode())
        row["mode_source"] = "tenant_override" if row.get("billing_mode") else "global_default"
        row["is_v2_plan"] = bool(row.get("plan_code"))
        return row

    def set_mode(self, tenant_pk: int, mode: str | None, *, actor_id: str | None) -> dict[str, Any]:
        """mode=None reverts the tenant to the global default. History keeps per-event mode."""
        new_mode = normalize_mode(mode, "") if mode else None
        if mode and not new_mode:
            raise ValueError("billing_mode inválido")
        with self.database.transaction() as conn:
            with conn.cursor() as cursor:
                before = self.get_config(tenant_pk, cursor)
                cursor.execute(
                    """
                    INSERT INTO tenant_billing_config (tenant_id, billing_mode, campaign_policy, updated_by_user_id)
                    VALUES (%s, %s, %s, %s)
                    ON DUPLICATE KEY UPDATE billing_mode=VALUES(billing_mode),
                        campaign_policy=VALUES(campaign_policy), updated_by_user_id=VALUES(updated_by_user_id)
                    """,
                    (tenant_pk, new_mode, self._campaign_policy(new_mode or self.default_mode()), actor_id),
                )
                after = self.get_config(tenant_pk, cursor)
        return {"old": before.get("billing_mode"), "new": new_mode, "old_effective": before["effective_mode"], "new_effective": after["effective_mode"]}

    def configure_plan(
        self,
        tenant_pk: int,
        *,
        plan_code: str,
        actor_id: str | None,
        billing_mode: str | None = None,
        operational_allowance: int | None = None,
        monthly_price: Decimal | None = None,
        require_paid: bool = False,
    ) -> dict[str, Any]:
        """Assign a V2 plan. require_paid=True: the allowance only arrives once the subscription is paid."""
        item = self.catalog.get_item(plan_code)
        if not item or item["kind"] != "plan":
            raise ValueError("Plano inexistente no catálogo")
        if item["status"] != "active":
            raise ValueError("Plano legado não pode ser atribuído a novas vendas")
        allowance = operational_allowance if operational_allowance is not None else item["operational_units"]
        price = monthly_price if monthly_price is not None else (Decimal(item["price"]) if item["price"] else None)
        if not allowance or allowance <= 0:
            raise ValueError("Plano sob consulta exige franquia operacional definida")
        if price is None:
            raise ValueError("Plano sob consulta exige preço mensal definido")
        mode = normalize_mode(billing_mode, "") if billing_mode else None
        now = self._clock()
        with self.database.transaction() as conn:
            with conn.cursor() as cursor:
                before = self.get_config(tenant_pk, cursor)
                effective_mode = mode or before.get("billing_mode") or None
                cursor.execute(
                    """
                    INSERT INTO tenant_billing_config
                        (tenant_id, billing_mode, catalog_version, plan_code, operational_allowance,
                         monthly_price, campaign_policy, billing_v2_active_from, updated_by_user_id)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON DUPLICATE KEY UPDATE
                        billing_mode=COALESCE(VALUES(billing_mode), billing_mode),
                        catalog_version=VALUES(catalog_version), plan_code=VALUES(plan_code),
                        operational_allowance=VALUES(operational_allowance), monthly_price=VALUES(monthly_price),
                        campaign_policy=VALUES(campaign_policy),
                        billing_v2_active_from=COALESCE(billing_v2_active_from, VALUES(billing_v2_active_from)),
                        updated_by_user_id=VALUES(updated_by_user_id)
                    """,
                    (
                        tenant_pk,
                        effective_mode,
                        item["catalog_version"],
                        plan_code,
                        int(allowance),
                        price,
                        self._campaign_policy(effective_mode or self.default_mode()),
                        now,
                        actor_id,
                    ),
                )
                cursor.execute(
                    "UPDATE tenants SET plan=%s WHERE id=%s",
                    (item["plan_key"] or plan_code, tenant_pk),
                )
        self._granted_cycles.pop(tenant_pk, None)
        grant = self.ensure_cycle_grant(tenant_pk, require_paid=require_paid)
        return {"before": before, "plan_code": plan_code, "operational_allowance": int(allowance), "monthly_price": str(price), "grant": grant}

    @staticmethod
    def _campaign_policy(mode: str) -> str:
        return "prepaid_credits" if mode == BillingMode.SOLUTION_PARTNER.value else "meta_direct"

    # ------------------------------------------------------------ grants
    def grant(
        self,
        tenant_pk: int,
        *,
        unit_type: str,
        units: int,
        source: str,
        grant_key: str,
        expires_at: datetime | None = None,
        cycle_start: datetime | None = None,
        cycle_end: datetime | None = None,
        catalog_item_code: str | None = None,
        purchase_id: str | None = None,
        actor_id: str | None = None,
        reason: str | None = None,
        amount: Decimal | None = None,
        cursor=None,
    ) -> dict[str, Any]:
        if units <= 0:
            raise ValueError("units must be positive")
        if unit_type not in {UnitType.OPERATIONAL.value, UnitType.MARKETING.value}:
            raise ValueError("unit_type inválido")

        def _do(cur) -> dict[str, Any]:
            cur.execute("SELECT id, granted FROM billing_entitlement_buckets WHERE grant_key=%s", (grant_key,))
            existing = cur.fetchone()
            if existing:
                return {"created": False, "bucket_id": existing["id"], "units": int(existing["granted"])}
            bucket_id = str(uuid.uuid4())
            try:
                cur.execute(
                    """
                    INSERT INTO billing_entitlement_buckets
                        (id, tenant_id, unit_type, source, granted, available, expires_at,
                         cycle_start, cycle_end, catalog_item_code, purchase_id, grant_key)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (bucket_id, tenant_pk, unit_type, source, units, units, expires_at,
                     cycle_start, cycle_end, catalog_item_code, purchase_id, grant_key),
                )
            except pymysql.err.IntegrityError:
                cur.execute("SELECT id, granted FROM billing_entitlement_buckets WHERE grant_key=%s", (grant_key,))
                row = cur.fetchone()
                return {"created": False, "bucket_id": row["id"] if row else None, "units": units}
            self._ledger(
                cur,
                tenant_pk,
                LedgerEntryType.GRANT,
                unit_type=unit_type,
                units=units,
                key=f"grant:{grant_key}",
                bucket_id=bucket_id,
                purchase_id=purchase_id,
                amount=amount,
                catalog_version=None,
                reason=reason or source,
                actor_id=actor_id,
            )
            return {"created": True, "bucket_id": bucket_id, "units": units}

        if cursor is not None:
            return _do(cursor)
        with self.database.transaction() as conn:
            with conn.cursor() as cur:
                return _do(cur)

    def ensure_cycle_grant(self, tenant_pk: int, *, require_paid: bool = True, cycle_hint: datetime | None = None) -> dict[str, Any] | None:
        now = cycle_hint or self._clock()
        cached = self._granted_cycles.get(tenant_pk)
        config = self.get_config(tenant_pk)
        if not config.get("plan_code") or not config.get("operational_allowance"):
            return None
        anchor = config.get("billing_v2_active_from") or now
        start, end = cycle_bounds(anchor, now)
        if cached == start:
            return None
        if require_paid:
            sub = self.database.fetch_one("SELECT status FROM subscriptions WHERE tenant_id=%s", (tenant_pk,))
            if sub and str(sub.get("status") or "").lower() not in _PAID_SUBSCRIPTION_STATUSES:
                return {"created": False, "reason": "subscription_not_paid"}
        result = self.grant(
            tenant_pk,
            unit_type=UnitType.OPERATIONAL.value,
            units=int(config["operational_allowance"]),
            source="plan",
            grant_key=f"plan:{tenant_pk}:{start:%Y%m%d%H%M%S}",
            expires_at=end,
            cycle_start=start,
            cycle_end=end,
            catalog_item_code=config.get("plan_code"),
            reason="monthly_plan_grant",
        )
        self._granted_cycles[tenant_pk] = start
        return result

    def expire_buckets(self) -> int:
        now = self._clock()
        expired = 0
        rows = self.database.fetch_all(
            "SELECT id FROM billing_entitlement_buckets WHERE expires_at IS NOT NULL AND expires_at <= %s AND available > 0",
            (now,),
        )
        for row in rows:
            with self.database.transaction() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT id, tenant_id, unit_type, available FROM billing_entitlement_buckets WHERE id=%s FOR UPDATE",
                        (row["id"],),
                    )
                    bucket = cur.fetchone()
                    if not bucket or int(bucket["available"]) <= 0:
                        continue
                    units = int(bucket["available"])
                    cur.execute(
                        "UPDATE billing_entitlement_buckets SET expired=expired+%s, available=0 WHERE id=%s",
                        (units, bucket["id"]),
                    )
                    self._ledger(
                        cur, int(bucket["tenant_id"]), LedgerEntryType.EXPIRE, unit_type=bucket["unit_type"],
                        units=units, key=f"expire:{bucket['id']}", bucket_id=bucket["id"], reason="cycle_end",
                    )
                    expired += units
        return expired

    # ------------------------------------------------------------ preflight
    def preflight(self, tenant_key: str, *, category: str, units: int = 1) -> GateDecision:
        """Read-only check (no reservation). Used before calling the LLM and for dry-runs."""
        try:
            tenant_pk = self.tenant_pk(tenant_key)
        except TenantNotFound:
            return GateDecision(False, "tenant_not_found", "Tenant não encontrado")
        self.ensure_cycle_grant(tenant_pk)
        cat = normalize_category(category)
        utype = unit_type_for(cat).value
        config = self.get_config(tenant_pk)
        mode = config["effective_mode"]
        entitlement = self._entitlement_for(utype, mode, config)
        if entitlement != Entitlement.BUCKET.value:
            return GateDecision(True, "ok", MSG_META_DIRECT if entitlement == Entitlement.META_DIRECT_TRACKING.value else None,
                                entitlement=entitlement, billing_mode=mode, category=cat, unit_type=utype)
        balance = self._balance(tenant_pk, utype)
        if balance["available"] < units:
            return GateDecision(False, self._blocked_code(utype), self._blocked_message(utype),
                                entitlement=entitlement, billing_mode=mode, category=cat, unit_type=utype, level="exhausted")
        return GateDecision(True, "ok", None, entitlement=entitlement, billing_mode=mode, category=cat, unit_type=utype)

    # ------------------------------------------------------------ reserve
    def reserve(
        self,
        tenant_key: str,
        *,
        category: str,
        category_source: str,
        source_path: str,
        idempotency_key: str,
        phone_number_id: str | None = None,
        units: int = 1,
        campaign_id: str | None = None,
        template_name: str | None = None,
        dry_run: bool = False,
    ) -> GateDecision:
        if dry_run:
            decision = self.preflight(tenant_key, category=category, units=units)
            decision.code = "dry_run" if decision.allowed else decision.code
            return decision
        try:
            tenant_pk = self.tenant_pk(tenant_key)
        except TenantNotFound:
            return GateDecision(False, "tenant_not_found", "Tenant não encontrado")
        self.ensure_cycle_grant(tenant_pk)

        def _tx() -> GateDecision:
            with self.database.transaction() as conn:
                with conn.cursor() as cur:
                    return self._reserve_one(
                        cur, tenant_pk,
                        category=category, category_source=category_source, source_path=source_path,
                        idempotency_key=idempotency_key, phone_number_id=phone_number_id, units=units,
                        campaign_id=campaign_id, template_name=template_name,
                    )

        try:
            decision = self._with_retry(_tx)
        except pymysql.err.IntegrityError:
            existing = self.database.fetch_one(
                "SELECT * FROM billing_reservations WHERE tenant_id=%s AND idempotency_key=%s",
                (tenant_pk, idempotency_key),
            )
            if existing:
                return self._decision_from_row(existing, duplicate=True)
            raise
        self._log_decision(tenant_key, decision, source_path=source_path)
        return decision

    @staticmethod
    def _log_decision(tenant_key: str, decision: GateDecision, *, source_path: str | None) -> None:
        if decision.duplicate:
            return
        common = {"tenant": tenant_key, "category": decision.category, "unit_type": decision.unit_type,
                  "mode": decision.billing_mode, "source": source_path}
        if not decision.allowed:
            log_billing_event("billing.blocked", code=decision.code, **common)
            return
        if decision.code != "reserved":
            return
        log_billing_event("billing.reserve", reservation=decision.reservation_id, entitlement=decision.entitlement,
                          level=decision.level, **common)
        log_billing_event("billing.rate_selected", reservation=decision.reservation_id, category=decision.category,
                          meta_unit_cost=decision.meta_unit_cost)

    def reserve_batch(
        self,
        tenant_key: str,
        *,
        category: str,
        category_source: str,
        source_path: str,
        recipients: list[dict[str, Any]],
        campaign_id: str | None = None,
        template_name: str | None = None,
        dry_run: bool = False,
    ) -> dict[str, Any]:
        """All-or-nothing reservation for campaigns (1 unit per recipient)."""
        count = len(recipients)
        if count == 0:
            return {"allowed": True, "reserved": 0, "reservations": []}
        try:
            tenant_pk = self.tenant_pk(tenant_key)
        except TenantNotFound:
            return {"allowed": False, "code": "tenant_not_found", "message": "Tenant não encontrado"}
        self.ensure_cycle_grant(tenant_pk)
        cat = normalize_category(category)
        utype = unit_type_for(cat).value
        config = self.get_config(tenant_pk)
        mode = config["effective_mode"]
        entitlement = self._entitlement_for(utype, mode, config)
        if dry_run:
            if entitlement == Entitlement.BUCKET.value:
                balance = self._balance(tenant_pk, utype)
                ok = balance["available"] >= count
                return {
                    "allowed": ok, "dry_run": True, "required": count, "available": balance["available"],
                    "code": "dry_run" if ok else self._blocked_code(utype),
                    "message": None if ok else self._blocked_message(utype),
                }
            return {"allowed": True, "dry_run": True, "required": count, "billing_mode": mode,
                    "message": MSG_META_DIRECT if entitlement == Entitlement.META_DIRECT_TRACKING.value else None}

        def _tx() -> dict[str, Any]:
            with self.database.transaction() as conn:
                with conn.cursor() as cur:
                    if entitlement == Entitlement.BUCKET.value:
                        buckets = self._lock_buckets(cur, tenant_pk, utype)
                        keys = [r["idempotency_key"] for r in recipients]
                        placeholders = ",".join(["%s"] * len(keys))
                        cur.execute(
                            f"SELECT idempotency_key FROM billing_reservations WHERE tenant_id=%s AND idempotency_key IN ({placeholders})",
                            (tenant_pk, *keys),
                        )
                        already = {r["idempotency_key"] for r in (cur.fetchall() or [])}
                        needed = sum(1 for k in keys if k not in already)
                        available = sum(int(b["available"]) for b in buckets)
                        if available < needed:
                            return {"allowed": False, "code": self._blocked_code(utype),
                                    "message": self._blocked_message(utype), "required": needed, "available": available}
                    results = []
                    for recipient in recipients:
                        decision = self._reserve_one(
                            cur, tenant_pk, category=cat, category_source=category_source, source_path=source_path,
                            idempotency_key=recipient["idempotency_key"], phone_number_id=recipient.get("phone_number_id"),
                            units=1, campaign_id=campaign_id, template_name=template_name,
                        )
                        if not decision.allowed:
                            raise _BatchAbort(decision)
                        results.append(decision.as_dict())
                    return {"allowed": True, "reserved": len(results), "reservations": results, "billing_mode": mode}

        try:
            result = self._with_retry(_tx)
        except _BatchAbort as abort:
            result = {"allowed": False, "code": abort.decision.code, "message": abort.decision.message}
        if result.get("allowed"):
            log_billing_event("billing.reserve", tenant=tenant_key, category=cat, unit_type=utype, mode=mode,
                              campaign=campaign_id, batch_units=result.get("reserved"), source=source_path)
        else:
            log_billing_event("billing.blocked", tenant=tenant_key, category=cat, unit_type=utype, mode=mode,
                              campaign=campaign_id, code=result.get("code"), required=result.get("required"),
                              available=result.get("available"), source=source_path)
        return result

    def _reserve_one(
        self,
        cur,
        tenant_pk: int,
        *,
        category: str,
        category_source: str,
        source_path: str,
        idempotency_key: str,
        phone_number_id: str | None,
        units: int,
        campaign_id: str | None,
        template_name: str | None,
    ) -> GateDecision:
        cur.execute(
            "SELECT * FROM billing_reservations WHERE tenant_id=%s AND idempotency_key=%s",
            (tenant_pk, idempotency_key),
        )
        existing = cur.fetchone()
        if existing:
            return self._decision_from_row(existing, duplicate=True)

        cat = normalize_category(category)
        utype = unit_type_for(cat).value
        config = self.get_config(tenant_pk, cur)
        mode = config["effective_mode"]
        entitlement = self._entitlement_for(utype, mode, config)
        now = self._clock()

        card = self.rate_engine.resolve(cat, market=settings.BILLING_MARKET, at=now.date(), cursor=cur)
        prior = 0
        if card is not None and card.free_allowance > 0:
            prior = self._prior_usage(cur, tenant_pk, cat, phone_number_id, card.allowance_scope, now)
        meta_unit_cost = effective_unit_cost(card, prior)

        bucket = None
        commercial_unit_price: Decimal | None = None
        if entitlement == Entitlement.BUCKET.value:
            buckets = self._lock_buckets(cur, tenant_pk, utype)
            candidates = [b for b in buckets if int(b["available"]) >= units and (b["expires_at"] is None or b["expires_at"] > now)]
            if not candidates:
                return GateDecision(False, self._blocked_code(utype), self._blocked_message(utype),
                                    entitlement=entitlement, billing_mode=mode, category=cat, unit_type=utype,
                                    level="exhausted")
            bucket = candidates[0]
            cur.execute(
                """
                UPDATE billing_entitlement_buckets
                SET available=available-%s, reserved=reserved+%s
                WHERE id=%s AND available >= %s
                """,
                (units, units, bucket["id"], units),
            )
            if cur.rowcount != 1:
                return GateDecision(False, self._blocked_code(utype), self._blocked_message(utype),
                                    entitlement=entitlement, billing_mode=mode, category=cat, unit_type=utype)
            commercial_unit_price = self._commercial_unit_price(cur, bucket, config)
        elif utype == UnitType.MARKETING.value:
            commercial_unit_price = None

        reservation_id = str(uuid.uuid4())
        cur.execute(
            """
            INSERT INTO billing_reservations
                (id, tenant_id, bucket_id, unit_type, units, category, category_source, billing_mode,
                 entitlement, source_path, phone_number_id, idempotency_key, status,
                 meta_rate_card_id, meta_unit_cost, meta_currency, meta_rate_version,
                 commercial_unit_price, catalog_version, campaign_id, template_name)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'reserved', %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                reservation_id, tenant_pk, bucket["id"] if bucket else None, utype, units, cat,
                (category_source or "unknown")[:64], mode, entitlement, (source_path or "system")[:32],
                phone_number_id, idempotency_key,
                card.id if card else None, meta_unit_cost, card.currency if card else None,
                card.version_code if card else None, commercial_unit_price, config.get("catalog_version"),
                campaign_id, (template_name or None),
            ),
        )
        self._ledger(
            cur, tenant_pk, LedgerEntryType.RESERVE, unit_type=utype, units=units,
            key=f"reserve:{reservation_id}", bucket_id=bucket["id"] if bucket else None,
            reservation_id=reservation_id, billing_mode=mode, category=cat,
            meta_cost=(meta_unit_cost * units) if meta_unit_cost is not None else None,
            meta_rate_card_id=card.id if card else None, catalog_version=config.get("catalog_version"),
            reason=source_path,
        )
        level = None
        if entitlement == Entitlement.BUCKET.value and utype == UnitType.OPERATIONAL.value:
            level = self._level_in_tx(cur, tenant_pk, now)
        return GateDecision(
            True, "reserved",
            MSG_META_DIRECT if entitlement == Entitlement.META_DIRECT_TRACKING.value else None,
            reservation_id=reservation_id, entitlement=entitlement, billing_mode=mode,
            category=cat, unit_type=utype, meta_unit_cost=meta_unit_cost, level=level,
        )

    # ------------------------------------------------------------ lifecycle
    def mark_accepted(self, tenant_key: str, reservation_id: str, provider_message_id: str) -> dict[str, Any]:
        tenant_pk = self.tenant_pk(tenant_key)
        provider_message_id = (provider_message_id or "").strip()
        if not provider_message_id:
            raise ValueError("provider_message_id obrigatório")

        def _tx() -> dict[str, Any]:
            with self.database.transaction() as conn:
                with conn.cursor() as cur:
                    res = self._lock_reservation(cur, tenant_pk, reservation_id)
                    if res is None:
                        return {"ok": False, "reason": "reservation_not_found"}
                    if res["provider_message_id"] and res["provider_message_id"] != provider_message_id:
                        return {"ok": False, "reason": "provider_message_id_mismatch"}
                    if res["status"] == ReservationStatus.RESERVED.value:
                        cur.execute(
                            """
                            UPDATE billing_reservations
                            SET status='accepted', provider_message_id=%s, accepted_at=%s
                            WHERE id=%s
                            """,
                            (provider_message_id, self._clock(), reservation_id),
                        )
                        res["status"] = ReservationStatus.ACCEPTED.value
                        res["provider_message_id"] = provider_message_id
                    elif res["status"] == ReservationStatus.RELEASED.value and not res["provider_message_id"]:
                        cur.execute(
                            "UPDATE billing_reservations SET provider_message_id=%s, reconciliation_required=1, reconciliation_note=%s WHERE id=%s",
                            (provider_message_id, "accepted_after_release", reservation_id),
                        )
                        return {"ok": True, "status": res["status"], "reconciliation_required": True}
                    # Replay statuses that arrived before acceptance (out of order).
                    cur.execute(
                        """
                        SELECT id, status, pricing_category, error_code FROM billing_message_status
                        WHERE tenant_id=%s AND provider_message_id=%s AND applied=0
                        ORDER BY id ASC
                        """,
                        (tenant_pk, provider_message_id),
                    )
                    pending = list(cur.fetchall() or [])
                    outcomes = []
                    for item in pending:
                        outcomes.append(self._apply_to_reservation(cur, res, item["status"], item.get("pricing_category")))
                        cur.execute("UPDATE billing_message_status SET applied=1 WHERE id=%s", (item["id"],))
                    return {"ok": True, "status": res["status"], "replayed": outcomes}

        result = self._with_retry(_tx)
        for outcome in result.get("replayed") or []:
            self._log_outcome(tenant_key, {**outcome, "reservation_id": reservation_id}, provider_status="replayed")
        return result

    def release(self, tenant_key: str, reservation_id: str, *, reason: str) -> dict[str, Any]:
        """Release a reservation whose send never reached Meta (gateway/API error)."""
        tenant_pk = self.tenant_pk(tenant_key)

        def _tx() -> dict[str, Any]:
            with self.database.transaction() as conn:
                with conn.cursor() as cur:
                    res = self._lock_reservation(cur, tenant_pk, reservation_id)
                    if res is None:
                        return {"ok": False, "reason": "reservation_not_found"}
                    if res["status"] != ReservationStatus.RESERVED.value:
                        return {"ok": True, "status": res["status"], "changed": False}
                    self._do_release(cur, res, reason=reason)
                    return {"ok": True, "status": ReservationStatus.RELEASED.value, "changed": True}

        result = self._with_retry(_tx)
        if result.get("changed"):
            log_billing_event("billing.release", tenant=tenant_key, reservation=reservation_id, reason=reason)
        return result

    def apply_status(
        self,
        tenant_key: str,
        provider_message_id: str,
        status: str,
        *,
        phone_number_id: str | None = None,
        pricing_category: str | None = None,
        pricing_billable: bool | None = None,
        error_code: str | None = None,
    ) -> dict[str, Any]:
        status = (status or "").strip().lower()
        provider_message_id = (provider_message_id or "").strip()
        if not provider_message_id or not status:
            return {"ok": False, "reason": "invalid_status"}
        try:
            tenant_pk = self.tenant_pk(tenant_key)
        except TenantNotFound:
            return {"ok": False, "reason": "tenant_not_found"}

        def _tx() -> dict[str, Any]:
            with self.database.transaction() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        INSERT IGNORE INTO billing_message_status
                            (tenant_id, provider_message_id, status, phone_number_id, pricing_category,
                             pricing_billable, error_code)
                        VALUES (%s, %s, %s, %s, %s, %s, %s)
                        """,
                        (tenant_pk, provider_message_id, status[:32], phone_number_id,
                         (pricing_category or None), None if pricing_billable is None else int(bool(pricing_billable)),
                         (error_code or None)),
                    )
                    if cur.rowcount == 0:
                        return {"ok": True, "duplicate": True}
                    status_id = cur.lastrowid
                    cur.execute(
                        "SELECT * FROM billing_reservations WHERE tenant_id=%s AND provider_message_id=%s FOR UPDATE",
                        (tenant_pk, provider_message_id),
                    )
                    res = cur.fetchone()
                    if res is None:
                        return {"ok": True, "pending": True}
                    outcome = self._apply_to_reservation(cur, res, status, pricing_category)
                    cur.execute("UPDATE billing_message_status SET applied=1 WHERE id=%s", (status_id,))
                    return {"ok": True, "reservation_id": res["id"], **outcome}

        result = self._with_retry(_tx)
        self._log_outcome(tenant_key, result, provider_status=status)
        return result

    @staticmethod
    def _log_outcome(tenant_key: str, outcome: dict[str, Any], *, provider_status: str) -> None:
        events = {"commit": "billing.commit", "release": "billing.release",
                  "reconciliation_required": "billing.reconciliation_required"}
        event = events.get(outcome.get("action") or "")
        if event:
            log_billing_event(event, tenant=tenant_key, reservation=outcome.get("reservation_id"),
                              provider_status=provider_status)

    def _apply_to_reservation(self, cur, res: dict[str, Any], status: str, pricing_category: str | None) -> dict[str, Any]:
        current = res["status"]
        rid = res["id"]
        if pricing_category and normalize_category(pricing_category) != res["category"]:
            cur.execute(
                "UPDATE billing_reservations SET reconciliation_required=1, reconciliation_note=%s WHERE id=%s",
                (f"category_divergence: meta={pricing_category[:24]} gate={res['category']}", rid),
            )
        if status in CONSUMING_STATUSES:
            if current in _OPEN_STATUSES:
                self._do_commit(cur, res, status)
                return {"action": "commit", "status": ReservationStatus.COMMITTED.value}
            if current == ReservationStatus.RELEASED.value:
                cur.execute(
                    "UPDATE billing_reservations SET reconciliation_required=1, reconciliation_note=%s, last_provider_status=%s WHERE id=%s",
                    (f"{status}_after_release", status, rid),
                )
                return {"action": "reconciliation_required", "status": current}
            return {"action": "noop", "status": current}
        if status == "failed":
            if current in _OPEN_STATUSES:
                self._do_release(cur, res, reason="provider_failed")
                return {"action": "release", "status": ReservationStatus.RELEASED.value}
            if current == ReservationStatus.COMMITTED.value:
                cur.execute(
                    "UPDATE billing_reservations SET reconciliation_required=1, reconciliation_note=%s, last_provider_status='failed' WHERE id=%s",
                    ("failed_after_commit", rid),
                )
                return {"action": "reconciliation_required", "status": current}
            return {"action": "noop", "status": current}
        if current in _OPEN_STATUSES:
            cur.execute("UPDATE billing_reservations SET last_provider_status=%s WHERE id=%s", (status[:32], rid))
        return {"action": "recorded", "status": current}

    def _do_commit(self, cur, res: dict[str, Any], provider_status: str) -> None:
        units = int(res["units"])
        tenant_pk = int(res["tenant_id"])
        if res["bucket_id"]:
            cur.execute(
                """
                UPDATE billing_entitlement_buckets
                SET reserved=reserved-%s, consumed=consumed+%s
                WHERE id=%s AND reserved >= %s
                """,
                (units, units, res["bucket_id"], units),
            )
            if cur.rowcount != 1:
                raise RuntimeError(f"bucket invariant violated on commit {res['id']}")
        now = self._clock()
        cur.execute(
            """
            UPDATE billing_reservations
            SET status='committed', last_provider_status=%s, finalized_at=%s
            WHERE id=%s
            """,
            (provider_status, now, res["id"]),
        )
        meta_unit = Decimal(str(res["meta_unit_cost"])) if res.get("meta_unit_cost") is not None else None
        meta_cost = meta_unit * units if meta_unit is not None else None
        self._ledger(
            cur, tenant_pk, LedgerEntryType.COMMIT, unit_type=res["unit_type"], units=units,
            key=f"commit:{res['id']}", bucket_id=res["bucket_id"], reservation_id=res["id"],
            billing_mode=res["billing_mode"], category=res["category"], meta_cost=meta_cost,
            meta_rate_card_id=res.get("meta_rate_card_id"), catalog_version=res.get("catalog_version"),
            amount=(Decimal(str(res["commercial_unit_price"])) * units) if res.get("commercial_unit_price") is not None else None,
            reason=provider_status,
        )
        product_units = 0 if res["entitlement"] == Entitlement.META_DIRECT_TRACKING.value else units
        provider_message_id = res.get("provider_message_id") or f"reservation:{res['id']}"
        cur.execute(
            """
            INSERT INTO usage_events
                (id, tenant_id, provider_message_id, phone_number_id, direction, category, category_source,
                 market, billing_mode, unit_type, event_type, quantity, product_units, meta_unit_cost,
                 meta_cost, meta_currency, rate_card_id, reservation_id, source_path, delivered_at,
                 billing_period, stripe_status, metadata)
            VALUES (%s, %s, %s, %s, 'outgoing', %s, %s, %s, %s, %s, 'delivered', %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'not_applicable', %s)
            ON DUPLICATE KEY UPDATE
                phone_number_id=VALUES(phone_number_id), category=VALUES(category),
                category_source=VALUES(category_source), billing_mode=VALUES(billing_mode),
                unit_type=VALUES(unit_type), product_units=VALUES(product_units),
                meta_unit_cost=VALUES(meta_unit_cost), meta_cost=VALUES(meta_cost),
                meta_currency=VALUES(meta_currency), rate_card_id=VALUES(rate_card_id),
                reservation_id=VALUES(reservation_id), source_path=VALUES(source_path)
            """,
            (
                str(uuid.uuid4()), tenant_pk, provider_message_id, res.get("phone_number_id"), res["category"],
                res["category_source"], settings.BILLING_MARKET, res["billing_mode"], res["unit_type"], units,
                product_units, meta_unit, meta_cost, res.get("meta_currency"), res.get("meta_rate_card_id"),
                res["id"], res["source_path"], now, now.strftime("%Y-%m"),
                json.dumps({"billing_v2": True, "campaign_id": res.get("campaign_id"), "template": res.get("template_name")}),
            ),
        )
        res["status"] = ReservationStatus.COMMITTED.value

    def _do_release(self, cur, res: dict[str, Any], *, reason: str) -> None:
        units = int(res["units"])
        if res["bucket_id"]:
            cur.execute(
                "SELECT expires_at FROM billing_entitlement_buckets WHERE id=%s FOR UPDATE", (res["bucket_id"],)
            )
            bucket = cur.fetchone() or {}
            expired = bucket.get("expires_at") is not None and bucket["expires_at"] <= self._clock()
            target = "expired" if expired else "available"
            cur.execute(
                f"""
                UPDATE billing_entitlement_buckets
                SET reserved=reserved-%s, {target}={target}+%s
                WHERE id=%s AND reserved >= %s
                """,
                (units, units, res["bucket_id"], units),
            )
            if cur.rowcount != 1:
                raise RuntimeError(f"bucket invariant violated on release {res['id']}")
        cur.execute(
            "UPDATE billing_reservations SET status='released', finalized_at=%s, last_provider_status=COALESCE(%s, last_provider_status) WHERE id=%s",
            (self._clock(), "failed" if reason == "provider_failed" else None, res["id"]),
        )
        self._ledger(
            cur, int(res["tenant_id"]), LedgerEntryType.RELEASE, unit_type=res["unit_type"], units=units,
            key=f"release:{res['id']}", bucket_id=res["bucket_id"], reservation_id=res["id"],
            billing_mode=res["billing_mode"], category=res["category"], reason=reason[:255],
        )
        res["status"] = ReservationStatus.RELEASED.value

    def mark_stale_pending(self, older_than_minutes: int | None = None) -> int:
        minutes = int(older_than_minutes or settings.BILLING_RESERVATION_STALE_MINUTES)
        cutoff = self._clock() - timedelta(minutes=minutes)
        return self.database.execute(
            """
            UPDATE billing_reservations
            SET status='pending_reconciliation', reconciliation_required=1,
                reconciliation_note=COALESCE(reconciliation_note, 'stale_without_final_status')
            WHERE status IN ('reserved', 'accepted') AND COALESCE(accepted_at, created_at) < %s
            """,
            (cutoff,),
        )

    def resolve_reconciliation(self, tenant_pk: int, reservation_id: str, *, action: str, actor_id: str | None, reason: str) -> dict[str, Any]:
        """Superadmin decision for pending/flagged reservations (audited by caller)."""
        if action not in {"commit", "release", "acknowledge"}:
            raise ValueError("ação inválida")
        with self.database.transaction() as conn:
            with conn.cursor() as cur:
                res = self._lock_reservation(cur, tenant_pk, reservation_id)
                if res is None:
                    raise LookupError("reserva não encontrada")
                before = res["status"]
                if action == "commit" and before in _OPEN_STATUSES:
                    self._do_commit(cur, res, "manual_reconciliation")
                elif action == "release" and before in _OPEN_STATUSES:
                    self._do_release(cur, res, reason=f"manual_reconciliation: {reason}"[:255])
                elif action in {"commit", "release"}:
                    raise ValueError(f"reserva em status {before} não pode receber {action}; use ajuste manual")
                cur.execute(
                    "UPDATE billing_reservations SET reconciliation_required=0, reconciliation_note=%s WHERE id=%s",
                    (f"resolved:{action} by {actor_id}: {reason}"[:255], reservation_id),
                )
                return {"before": before, "after": res["status"], "action": action}

    # ------------------------------------------------------------ summary
    def summary(self, tenant_key: str) -> dict[str, Any]:
        tenant_pk = self.tenant_pk(tenant_key)
        self.ensure_cycle_grant(tenant_pk)
        now = self._clock()
        config = self.get_config(tenant_pk)
        mode = config["effective_mode"]
        rows = self.database.fetch_all(
            """
            SELECT unit_type, source, granted, available, reserved, consumed, expired, expires_at, cycle_start, cycle_end
            FROM billing_entitlement_buckets
            WHERE tenant_id=%s AND (expires_at IS NULL OR expires_at > %s OR reserved > 0)
            """,
            (tenant_pk, now),
        )
        op_plan = [r for r in rows if r["unit_type"] == "operational" and r["source"] == "plan" and (r["expires_at"] is None or r["expires_at"] > now)]
        op_extra = [r for r in rows if r["unit_type"] == "operational" and r["source"] != "plan" and (r["expires_at"] is None or r["expires_at"] > now)]
        mk = [r for r in rows if r["unit_type"] == "marketing"]

        def _sum(items, key):
            return sum(int(i[key] or 0) for i in items)

        allowance = int(config.get("operational_allowance") or 0)
        plan_used = _sum(op_plan, "consumed") + _sum(op_plan, "reserved")
        cycle = op_plan[0] if op_plan else None
        topup_available = _sum(op_extra, "available")
        plan_available = _sum(op_plan, "available")
        level = usage_level(plan_used, allowance) if config["is_v2_plan"] else "ok"
        blocked = config["is_v2_plan"] and plan_available + topup_available <= 0
        counts = self.database.fetch_all(
            """
            SELECT category, status, COUNT(*) AS total, SUM(units) AS units
            FROM billing_reservations
            WHERE tenant_id=%s AND created_at >= %s
            GROUP BY category, status
            """,
            (tenant_pk, (cycle["cycle_start"] if cycle else now.replace(day=1, hour=0, minute=0, second=0, microsecond=0))),
        )
        plan_item = self.catalog.get_item(config["plan_code"]) if config.get("plan_code") else None
        return {
            "tenant_id": tenant_key,
            "billing_v2_enabled": self.enabled,
            "billing_mode": mode,
            "billing_mode_source": config["mode_source"],
            "billing_mode_label": "Atende Ai (créditos)" if mode == BillingMode.SOLUTION_PARTNER.value else "Cliente paga Meta diretamente",
            "meta_notice": MSG_META_DIRECT if mode == BillingMode.CUSTOMER_DIRECT.value else None,
            "is_v2_plan": config["is_v2_plan"],
            "plan": plan_item,
            "catalog_version": config.get("catalog_version"),
            "monthly_price": str(config["monthly_price"]) if config.get("monthly_price") is not None else None,
            "cycle_start": cycle["cycle_start"] if cycle else None,
            "cycle_end": cycle["cycle_end"] if cycle else None,
            "operational": {
                "allowance": allowance,
                "used": plan_used,
                "plan_available": plan_available,
                "topup_available": topup_available,
                "total_available": plan_available + topup_available,
                "reserved": _sum(op_plan, "reserved") + _sum(op_extra, "reserved"),
                "level": level,
                "blocked": blocked,
                "unmetered_legacy": not config["is_v2_plan"],
            },
            "marketing": {
                "available": _sum(mk, "available"),
                "reserved": _sum(mk, "reserved"),
                "consumed": _sum(mk, "consumed"),
                "requires_credits": mode == BillingMode.SOLUTION_PARTNER.value,
                "unit_price": str(self.catalog.marketing_unit_price() or "") or None,
                "packs": self.catalog.marketing_pack_offers() if mode == BillingMode.SOLUTION_PARTNER.value else [],
            },
            "by_category": [
                {"category": c["category"], "status": c["status"], "count": int(c["total"] or 0), "units": int(c["units"] or 0)}
                for c in counts
            ],
            "topup_offers": self.catalog.topup_offers() if config["is_v2_plan"] else [],
        }

    # ------------------------------------------------------------ helpers
    def _entitlement_for(self, unit_type: str, mode: str, config: dict[str, Any]) -> str:
        if unit_type == UnitType.OPERATIONAL.value:
            return Entitlement.BUCKET.value if config.get("plan_code") else Entitlement.LEGACY_UNMETERED.value
        if mode == BillingMode.SOLUTION_PARTNER.value:
            return Entitlement.BUCKET.value
        return Entitlement.META_DIRECT_TRACKING.value

    @staticmethod
    def _blocked_code(unit_type: str) -> str:
        return "marketing_credits_insufficient" if unit_type == UnitType.MARKETING.value else "operational_allowance_exhausted"

    @staticmethod
    def _blocked_message(unit_type: str) -> str:
        return MSG_MARKETING_INSUFFICIENT if unit_type == UnitType.MARKETING.value else MSG_OPERATIONAL_EXHAUSTED

    def _lock_buckets(self, cur, tenant_pk: int, unit_type: str) -> list[dict[str, Any]]:
        now = self._clock()
        cur.execute(
            """
            SELECT id, source, available, reserved, expires_at, catalog_item_code, purchase_id, granted, created_at
            FROM billing_entitlement_buckets
            WHERE tenant_id=%s AND unit_type=%s
            ORDER BY (expires_at IS NULL) ASC, expires_at ASC, created_at ASC
            FOR UPDATE
            """,
            (tenant_pk, unit_type),
        )
        rows = list(cur.fetchall() or [])
        return [r for r in rows if r["expires_at"] is None or r["expires_at"] > now]

    def _balance(self, tenant_pk: int, unit_type: str) -> dict[str, int]:
        row = self.database.fetch_one(
            """
            SELECT COALESCE(SUM(available),0) AS available, COALESCE(SUM(reserved),0) AS reserved
            FROM billing_entitlement_buckets
            WHERE tenant_id=%s AND unit_type=%s AND (expires_at IS NULL OR expires_at > %s)
            """,
            (tenant_pk, unit_type, self._clock()),
        ) or {}
        return {"available": int(row.get("available") or 0), "reserved": int(row.get("reserved") or 0)}

    def _level_in_tx(self, cur, tenant_pk: int, now: datetime) -> str:
        cur.execute(
            """
            SELECT COALESCE(SUM(granted),0) AS granted, COALESCE(SUM(consumed+reserved),0) AS used
            FROM billing_entitlement_buckets
            WHERE tenant_id=%s AND unit_type='operational' AND source='plan' AND expires_at > %s
            """,
            (tenant_pk, now),
        )
        row = cur.fetchone() or {}
        return usage_level(int(row.get("used") or 0), int(row.get("granted") or 0))

    def _commercial_unit_price(self, cur, bucket: dict[str, Any], config: dict[str, Any]) -> Decimal | None:
        if bucket.get("purchase_id"):
            cur.execute("SELECT unit_price FROM billing_topup_purchases WHERE id=%s", (bucket["purchase_id"],))
            row = cur.fetchone()
            if row and row.get("unit_price") is not None:
                return Decimal(str(row["unit_price"]))
        if bucket.get("source") == "plan" and config.get("monthly_price") is not None and int(bucket.get("granted") or 0) > 0:
            return (Decimal(str(config["monthly_price"])) / Decimal(int(bucket["granted"]))).quantize(Decimal("0.000001"))
        return None

    def _prior_usage(self, cur, tenant_pk: int, category: str, phone_number_id: str | None, scope: str | None, now: datetime) -> int:
        period_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        if scope == "phone_number" and phone_number_id:
            cur.execute(
                """
                SELECT COUNT(*) AS total FROM billing_reservations
                WHERE tenant_id=%s AND category=%s AND phone_number_id=%s AND created_at >= %s
                  AND status IN ('reserved','accepted','committed','pending_reconciliation')
                """,
                (tenant_pk, category, phone_number_id, period_start),
            )
        else:
            cur.execute(
                """
                SELECT COUNT(*) AS total FROM billing_reservations
                WHERE tenant_id=%s AND category=%s AND created_at >= %s
                  AND status IN ('reserved','accepted','committed','pending_reconciliation')
                """,
                (tenant_pk, category, period_start),
            )
        return int((cur.fetchone() or {}).get("total") or 0)

    def _lock_reservation(self, cur, tenant_pk: int, reservation_id: str) -> dict[str, Any] | None:
        cur.execute(
            "SELECT * FROM billing_reservations WHERE id=%s AND tenant_id=%s FOR UPDATE",
            (reservation_id, tenant_pk),
        )
        row = cur.fetchone()
        return dict(row) if row else None

    def _ledger(
        self,
        cur,
        tenant_pk: int,
        entry_type: LedgerEntryType,
        *,
        unit_type: str,
        units: int,
        key: str,
        bucket_id: str | None = None,
        reservation_id: str | None = None,
        purchase_id: str | None = None,
        billing_mode: str | None = None,
        category: str | None = None,
        amount: Decimal | None = None,
        meta_cost: Decimal | None = None,
        meta_rate_card_id: int | None = None,
        catalog_version: str | None = None,
        reason: str | None = None,
        actor_id: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        cur.execute(
            """
            INSERT IGNORE INTO billing_ledger
                (tenant_id, entry_type, unit_type, units, bucket_id, reservation_id, purchase_id,
                 idempotency_key, billing_mode, category, amount, currency, meta_cost, meta_rate_card_id,
                 catalog_version, reason, actor_user_id, metadata)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'BRL', %s, %s, %s, %s, %s, %s)
            """,
            (
                tenant_pk, entry_type.value, unit_type, units, bucket_id, reservation_id, purchase_id,
                key[:190], billing_mode, category, amount, meta_cost, meta_rate_card_id, catalog_version,
                (reason or None) and reason[:255], actor_id, json.dumps(metadata) if metadata else None,
            ),
        )

    def _decision_from_row(self, row: dict[str, Any], *, duplicate: bool) -> GateDecision:
        allowed = row["status"] != ReservationStatus.RELEASED.value
        return GateDecision(
            allowed, "duplicate" if allowed else "released",
            None, reservation_id=row["id"], entitlement=row["entitlement"], billing_mode=row["billing_mode"],
            category=row["category"], unit_type=row["unit_type"],
            meta_unit_cost=Decimal(str(row["meta_unit_cost"])) if row.get("meta_unit_cost") is not None else None,
            duplicate=duplicate,
        )

    @staticmethod
    def _with_retry(fn: Callable[[], Any], attempts: int = 4) -> Any:
        for attempt in range(attempts):
            try:
                return fn()
            except pymysql.err.OperationalError as exc:
                code = exc.args[0] if exc.args else None
                if code in _DEADLOCK_CODES and attempt < attempts - 1:
                    time.sleep(0.02 * (attempt + 1))
                    continue
                raise


class _BatchAbort(Exception):
    def __init__(self, decision: GateDecision):
        super().__init__(decision.code)
        self.decision = decision
