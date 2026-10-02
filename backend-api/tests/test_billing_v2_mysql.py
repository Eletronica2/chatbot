"""Billing V2 integration tests against a real, disposable MySQL database.

Set BILLING_V2_TEST_DATABASE_URL to a scratch schema (never production);
the suite is skipped otherwise.
"""
import os
import threading
import uuid
from datetime import datetime, timedelta
from decimal import Decimal

import pytest

DB_URL = os.environ.get("BILLING_V2_TEST_DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DB_URL, reason="BILLING_V2_TEST_DATABASE_URL not set")

if DB_URL:
    from app.db.mysql import MySQLDatabase
    from app.services.billing_catalog_service import BillingCatalogService
    from app.services.billing_gate import BillingGate
    from app.services.billing_topup_service import BillingTopupService
    from app.services.meta_rate_engine import MetaRateEngine

SP = "solution_partner_credit_line"
CD = "customer_direct"


@pytest.fixture(scope="module")
def db():
    database = MySQLDatabase(DB_URL)
    database.bootstrap(default_tenant_key="default", default_tenant_name="Default", default_tenant_email="default@example.com")
    return database


@pytest.fixture()
def gate(db):
    engine = MetaRateEngine(db)
    catalog = BillingCatalogService(db)
    return BillingGate(db, engine, catalog)


@pytest.fixture()
def topups(db, gate):
    return BillingTopupService(db, gate.catalog, gate)


def _tenant(db, *, subscription_status: str = "active") -> tuple[str, int]:
    key = f"bv2-{uuid.uuid4().hex[:12]}"
    pk = db.insert(
        "INSERT INTO tenants (external_key, name, email, plan, status) VALUES (%s, %s, %s, 'starter', 'active')",
        (key, f"Tenant {key}", f"{key}@example.com"),
    )
    db.execute(
        "INSERT INTO subscriptions (tenant_id, plan, status, renewal_date) VALUES (%s, 'starter', %s, %s)",
        (pk, subscription_status, datetime.utcnow() + timedelta(days=30)),
    )
    return key, pk


def _bucket_totals(db, pk: int, unit_type: str) -> dict[str, int]:
    row = db.fetch_one(
        """
        SELECT COALESCE(SUM(available),0) AS available, COALESCE(SUM(reserved),0) AS reserved,
               COALESCE(SUM(consumed),0) AS consumed, COALESCE(SUM(granted),0) AS granted,
               COALESCE(SUM(expired),0) AS expired
        FROM billing_entitlement_buckets WHERE tenant_id=%s AND unit_type=%s
        """,
        (pk, unit_type),
    )
    return {k: int(v) for k, v in row.items()}


def _plan_tenant(db, gate, *, allowance: int = 1000, mode: str | None = None) -> tuple[str, int]:
    key, pk = _tenant(db)
    gate.configure_plan(pk, plan_code="PLAN_INICIAL_2026_10", actor_id="test", billing_mode=mode,
                        operational_allowance=allowance, monthly_price=Decimal("197"))
    return key, pk


def _reserve(gate, key, category="SERVICE", idem=None, **kw):
    return gate.reserve(key, category=category, category_source="test", source_path="ai",
                        idempotency_key=idem or f"k:{uuid.uuid4()}", **kw)


def _ledger_count(db, pk, entry_type):
    return int(db.fetch_one("SELECT COUNT(*) AS n FROM billing_ledger WHERE tenant_id=%s AND entry_type=%s",
                            (pk, entry_type))["n"])


# ----------------------------------------------------------------- schema / catalog
def test_bootstrap_is_idempotent_and_seeds_catalog(db):
    db.bootstrap(default_tenant_key="default", default_tenant_name="Default", default_tenant_email="default@example.com")
    codes = {r["code"]: r for r in db.fetch_all("SELECT code, price, operational_units, status FROM billing_catalog_items")}
    assert codes["PLAN_INICIAL_2026_10"]["price"] == Decimal("197") and codes["PLAN_INICIAL_2026_10"]["operational_units"] == 1000
    assert codes["PLAN_ESSENCIAL_2026_10"]["operational_units"] == 3000
    assert codes["PLAN_CRESCIMENTO_2026_10"]["operational_units"] == 6000
    assert codes["PLAN_PROFISSIONAL_2026_10"]["operational_units"] == 12000
    assert codes["PLAN_EMPRESARIAL_2026_10"]["price"] is None
    assert codes["TOPUP_OPERATIONAL_500_2026_10"]["price"] == Decimal("49.90")
    assert codes["TOPUP_OPERATIONAL_1000_2026_10"]["price"] == Decimal("89.90")
    assert codes["MARKETING_CREDIT_2026_10"]["price"] == Decimal("0.55")
    assert codes["PLAN_LEGACY_STARTER"]["status"] == "legacy"
    dup = db.fetch_one("SELECT COUNT(*) AS n FROM billing_catalog_items GROUP BY code HAVING n > 1")
    assert dup is None
    idx = {r["INDEX_NAME"] for r in db.fetch_all(
        "SELECT DISTINCT INDEX_NAME FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='meta_rate_cards'")}
    assert "uq_meta_rate_v2" in idx and "uq_meta_rate" not in idx


def test_rate_engine_resolves_effective_version(gate):
    card = gate.rate_engine.resolve("MARKETING", market="BR")
    assert card is not None
    assert card.unit_price == Decimal("0.321700")
    assert gate.rate_engine.worst_case_operational(market="BR") == Decimal("0.035000")
    current = [c for c in gate.rate_engine.list_cards(market="BR") if c["current"] and c["category"] == "MARKETING"]
    assert len(current) == 1 and current[0]["version_code"] == card.version_code


# ----------------------------------------------------------------- operational lifecycle (§134/§135)
def test_reserve_delivered_commits_exactly_once(db, gate):
    key, pk = _plan_tenant(db, gate)
    before = _bucket_totals(db, pk, "operational")
    assert before["available"] == 1000
    decision = _reserve(gate, key)
    assert decision.allowed and decision.entitlement == "bucket"
    mid = _bucket_totals(db, pk, "operational")
    assert mid["available"] == 999 and mid["reserved"] == 1
    gate.mark_accepted(key, decision.reservation_id, "wamid.TEST1")
    assert gate.apply_status(key, "wamid.TEST1", "sent")["action"] == "recorded"
    assert gate.apply_status(key, "wamid.TEST1", "delivered")["action"] == "commit"
    assert gate.apply_status(key, "wamid.TEST1", "delivered").get("duplicate") is True
    assert gate.apply_status(key, "wamid.TEST1", "read")["action"] == "noop"
    after = _bucket_totals(db, pk, "operational")
    assert after == {**after, "available": 999, "reserved": 0, "consumed": 1}
    assert _ledger_count(db, pk, "COMMIT") == 1
    usage = db.fetch_all("SELECT product_units, billing_mode FROM usage_events WHERE tenant_id=%s", (pk,))
    assert len(usage) == 1 and int(usage[0]["product_units"]) == 1


def test_failed_releases_and_restores_balance(db, gate):
    key, pk = _plan_tenant(db, gate)
    decision = _reserve(gate, key)
    gate.mark_accepted(key, decision.reservation_id, "wamid.FAIL1")
    assert _bucket_totals(db, pk, "operational")["available"] == 999
    assert gate.apply_status(key, "wamid.FAIL1", "failed", error_code="131026")["action"] == "release"
    totals = _bucket_totals(db, pk, "operational")
    assert totals["available"] == 1000 and totals["reserved"] == 0 and totals["consumed"] == 0


def test_gateway_error_release_before_meta(db, gate):
    key, pk = _plan_tenant(db, gate)
    decision = _reserve(gate, key)
    assert gate.release(key, decision.reservation_id, reason="gateway_error")["changed"] is True
    assert gate.release(key, decision.reservation_id, reason="gateway_error")["changed"] is False
    assert _bucket_totals(db, pk, "operational")["available"] == 1000


def test_failed_after_commit_flags_reconciliation_without_refund(db, gate):
    key, pk = _plan_tenant(db, gate)
    decision = _reserve(gate, key)
    gate.mark_accepted(key, decision.reservation_id, "wamid.FAC")
    gate.apply_status(key, "wamid.FAC", "delivered")
    assert gate.apply_status(key, "wamid.FAC", "failed")["action"] == "reconciliation_required"
    res = db.fetch_one("SELECT status, reconciliation_required FROM billing_reservations WHERE id=%s", (decision.reservation_id,))
    assert res["status"] == "committed" and int(res["reconciliation_required"]) == 1
    assert _bucket_totals(db, pk, "operational")["consumed"] == 1


def test_out_of_order_status_before_acceptance_is_replayed(db, gate):
    key, pk = _plan_tenant(db, gate)
    decision = _reserve(gate, key)
    assert gate.apply_status(key, "wamid.OOO", "delivered").get("pending") is True
    assert _bucket_totals(db, pk, "operational")["consumed"] == 0
    result = gate.mark_accepted(key, decision.reservation_id, "wamid.OOO")
    assert [o["action"] for o in result["replayed"]] == ["commit"]
    totals = _bucket_totals(db, pk, "operational")
    assert totals["consumed"] == 1 and totals["reserved"] == 0


def test_status_without_reservation_never_consumes(db, gate):
    key, pk = _plan_tenant(db, gate)
    before = _bucket_totals(db, pk, "operational")
    assert gate.apply_status(key, "wamid.INBOUND_OR_UNKNOWN", "delivered").get("pending") is True
    assert _bucket_totals(db, pk, "operational") == before


def test_idempotent_reserve_same_key(db, gate):
    key, pk = _plan_tenant(db, gate)
    first = _reserve(gate, key, idem="reply:msg-1")
    second = _reserve(gate, key, idem="reply:msg-1")
    assert second.duplicate is True and second.reservation_id == first.reservation_id
    assert _bucket_totals(db, pk, "operational")["reserved"] == 1


def test_exhausted_blocks_and_topup_unblocks(db, gate, topups):
    key, pk = _plan_tenant(db, gate, allowance=2)
    assert _reserve(gate, key).allowed and _reserve(gate, key).allowed
    blocked = _reserve(gate, key)
    assert blocked.allowed is False and blocked.code == "operational_allowance_exhausted"
    assert gate.preflight(key, category="SERVICE").allowed is False
    purchase = topups.create_purchase(pk, item_code="TOPUP_OPERATIONAL_500_2026_10", units=None, actor_id="test")
    first = topups.mark_paid_and_grant(purchase["id"], provider_payment_id="pi_test_1", actor_id="test", reason="test",
                                       expected_tenant_pk=pk, expected_total=Decimal("49.90"))
    second = topups.mark_paid_and_grant(purchase["id"], provider_payment_id="pi_test_1", actor_id="test", reason="test")
    assert first["created"] is True and second["created"] is False
    topup_buckets = db.fetch_all("SELECT expires_at, granted FROM billing_entitlement_buckets WHERE tenant_id=%s AND source='topup'", (pk,))
    assert len(topup_buckets) == 1 and topup_buckets[0]["expires_at"] is None and int(topup_buckets[0]["granted"]) == 500
    assert _reserve(gate, key).allowed is True
    summary = gate.summary(key)
    assert summary["operational"]["topup_available"] == 499
    assert summary["operational"]["level"] == "exhausted"


def test_topup_rejects_wrong_tenant_or_amount(db, gate, topups):
    key, pk = _plan_tenant(db, gate)
    purchase = topups.create_purchase(pk, item_code="TOPUP_OPERATIONAL_1000_2026_10", units=None, actor_id="test")
    with pytest.raises(ValueError):
        topups.mark_paid_and_grant(purchase["id"], provider_payment_id=None, actor_id="t", reason="t", expected_tenant_pk=pk + 999)
    with pytest.raises(ValueError):
        topups.mark_paid_and_grant(purchase["id"], provider_payment_id=None, actor_id="t", reason="t", expected_total=Decimal("1.00"))


def test_plan_credits_expire_topups_do_not(db, gate):
    key, pk = _plan_tenant(db, gate, allowance=10)
    gate.grant(pk, unit_type="operational", units=5, source="topup", grant_key=f"manual:{uuid.uuid4()}")
    db.execute("UPDATE billing_entitlement_buckets SET expires_at=%s WHERE tenant_id=%s AND source='plan'",
               (datetime.utcnow() - timedelta(minutes=1), pk))
    gate.expire_buckets()
    rows = {r["source"]: r for r in db.fetch_all(
        "SELECT source, available, expired FROM billing_entitlement_buckets WHERE tenant_id=%s", (pk,))}
    assert int(rows["plan"]["available"]) == 0 and int(rows["plan"]["expired"]) == 10
    assert int(rows["topup"]["available"]) == 5


def test_cycle_grant_is_idempotent_and_requires_paid_subscription(db, gate):
    key, pk = _plan_tenant(db, gate)
    gate._granted_cycles.clear()
    gate.ensure_cycle_grant(pk)
    gate._granted_cycles.clear()
    gate.ensure_cycle_grant(pk)
    plan_buckets = db.fetch_one("SELECT COUNT(*) AS n FROM billing_entitlement_buckets WHERE tenant_id=%s AND source='plan'", (pk,))
    assert int(plan_buckets["n"]) == 1
    unpaid_key, unpaid_pk = _tenant(db, subscription_status="past_due")
    db.execute(
        "INSERT INTO tenant_billing_config (tenant_id, plan_code, catalog_version, operational_allowance, monthly_price, billing_v2_active_from) "
        "VALUES (%s, 'PLAN_INICIAL_2026_10', '2026-10', 1000, 197, %s)",
        (unpaid_pk, datetime.utcnow()),
    )
    assert gate.ensure_cycle_grant(unpaid_pk) == {"created": False, "reason": "subscription_not_paid"}
    assert _bucket_totals(db, unpaid_pk, "operational")["granted"] == 0


def test_legacy_tenant_is_unmetered_and_not_migrated(db, gate):
    key, pk = _tenant(db)
    decision = _reserve(gate, key)
    assert decision.allowed and decision.entitlement == "legacy_unmetered"
    assert _bucket_totals(db, pk, "operational")["granted"] == 0
    assert gate.get_config(pk)["is_v2_plan"] is False


# ----------------------------------------------------------------- concurrency
def test_parallel_reservations_never_go_negative(db, gate):
    key, pk = _plan_tenant(db, gate, allowance=5)
    results: list = []
    errors: list = []

    def worker(i: int) -> None:
        try:
            local = BillingGate(db, gate.rate_engine, gate.catalog)
            results.append(_reserve(local, key, idem=f"par:{i}"))
        except Exception as exc:  # pragma: no cover - surfaced by assertion below
            errors.append(exc)

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(20)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert errors == []
    assert sum(1 for r in results if r.allowed) == 5
    totals = _bucket_totals(db, pk, "operational")
    assert totals["available"] == 0 and totals["reserved"] == 5
    assert db.fetch_one("SELECT MIN(available) AS m FROM billing_entitlement_buckets WHERE tenant_id=%s", (pk,))["m"] >= 0


def test_parallel_duplicate_delivered_commits_once(db, gate):
    key, pk = _plan_tenant(db, gate)
    decision = _reserve(gate, key)
    gate.mark_accepted(key, decision.reservation_id, "wamid.PARDUP")
    threads = [threading.Thread(target=lambda: BillingGate(db, gate.rate_engine, gate.catalog).apply_status(key, "wamid.PARDUP", "delivered")) for _ in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert _bucket_totals(db, pk, "operational")["consumed"] == 1
    assert _ledger_count(db, pk, "COMMIT") == 1


# ----------------------------------------------------------------- marketing (§136/§137)
def test_marketing_solution_partner_prepaid_credits(db, gate):
    key, pk = _plan_tenant(db, gate, mode=SP)
    blocked = _reserve(gate, key, category="MARKETING")
    assert blocked.allowed is False and blocked.message == "Saldo insuficiente de créditos de campanha."
    gate.grant(pk, unit_type="marketing", units=100, source="admin", grant_key=f"mk:{uuid.uuid4()}")
    ok = _reserve(gate, key, category="MARKETING")
    totals = _bucket_totals(db, pk, "marketing")
    assert totals["available"] == 99 and totals["reserved"] == 1
    gate.mark_accepted(key, ok.reservation_id, "wamid.MK1")
    gate.apply_status(key, "wamid.MK1", "delivered", pricing_category="marketing")
    totals = _bucket_totals(db, pk, "marketing")
    assert totals["available"] == 99 and totals["reserved"] == 0 and totals["consumed"] == 1
    fail = _reserve(gate, key, category="MARKETING")
    gate.mark_accepted(key, fail.reservation_id, "wamid.MK2")
    gate.apply_status(key, "wamid.MK2", "failed")
    assert _bucket_totals(db, pk, "marketing")["available"] == 99
    assert _bucket_totals(db, pk, "operational")["consumed"] == 0


def test_marketing_customer_direct_tracks_without_consuming(db, gate):
    key, pk = _plan_tenant(db, gate, mode=CD)
    gate.grant(pk, unit_type="marketing", units=100, source="admin", grant_key=f"mk:{uuid.uuid4()}")
    decision = _reserve(gate, key, category="MARKETING")
    assert decision.allowed and decision.entitlement == "meta_direct_tracking"
    assert decision.message == "Tarifas da Meta são cobradas diretamente pela Meta."
    gate.mark_accepted(key, decision.reservation_id, "wamid.CD1")
    gate.apply_status(key, "wamid.CD1", "delivered")
    assert _bucket_totals(db, pk, "marketing")["available"] == 100
    usage = db.fetch_one("SELECT product_units, meta_cost, billing_mode FROM usage_events WHERE tenant_id=%s AND provider_message_id='wamid.CD1'", (pk,))
    assert int(usage["product_units"]) == 0
    assert usage["meta_cost"] == Decimal("0.321700")
    assert usage["billing_mode"] == CD


def test_campaign_batch_is_all_or_nothing(db, gate):
    key, pk = _plan_tenant(db, gate, mode=SP)
    gate.grant(pk, unit_type="marketing", units=3, source="admin", grant_key=f"mk:{uuid.uuid4()}")
    recipients = [{"idempotency_key": f"camp:{uuid.uuid4()}"} for _ in range(5)]
    result = gate.reserve_batch(key, category="MARKETING", category_source="template_approved_category",
                                source_path="campaign", recipients=recipients)
    assert result["allowed"] is False
    assert _bucket_totals(db, pk, "marketing")["available"] == 3
    ok = gate.reserve_batch(key, category="MARKETING", category_source="template_approved_category",
                            source_path="campaign", recipients=recipients[:3])
    assert ok["allowed"] is True and ok["reserved"] == 3
    assert _bucket_totals(db, pk, "marketing")["available"] == 0


def test_mode_switch_keeps_history_snapshot(db, gate):
    key, pk = _plan_tenant(db, gate, mode=SP)
    gate.grant(pk, unit_type="marketing", units=10, source="admin", grant_key=f"mk:{uuid.uuid4()}")
    first = _reserve(gate, key, category="MARKETING")
    gate.set_mode(pk, CD, actor_id="test")
    second = _reserve(gate, key, category="MARKETING")
    modes = {r["id"]: r["billing_mode"] for r in db.fetch_all("SELECT id, billing_mode FROM billing_reservations WHERE tenant_id=%s", (pk,))}
    assert modes[first.reservation_id] == SP and modes[second.reservation_id] == CD
    assert gate.set_mode(pk, None, actor_id="test")["new_effective"] == CD


# ----------------------------------------------------------------- dry-run (§138)
def test_dry_run_changes_nothing(db, gate):
    key, pk = _plan_tenant(db, gate, mode=SP)
    gate.grant(pk, unit_type="marketing", units=5, source="admin", grant_key=f"mk:{uuid.uuid4()}")
    before_op = _bucket_totals(db, pk, "operational")
    before_mk = _bucket_totals(db, pk, "marketing")
    before_res = db.fetch_one("SELECT COUNT(*) AS n FROM billing_reservations WHERE tenant_id=%s", (pk,))["n"]
    assert _reserve(gate, key, dry_run=True).code == "dry_run"
    assert gate.reserve_batch(key, category="MARKETING", category_source="t", source_path="campaign",
                              recipients=[{"idempotency_key": "x"}], dry_run=True)["dry_run"] is True
    assert _bucket_totals(db, pk, "operational") == before_op
    assert _bucket_totals(db, pk, "marketing") == before_mk
    assert db.fetch_one("SELECT COUNT(*) AS n FROM billing_reservations WHERE tenant_id=%s", (pk,))["n"] == before_res
    assert db.fetch_one("SELECT COUNT(*) AS n FROM usage_events WHERE tenant_id=%s", (pk,))["n"] == 0


# ----------------------------------------------------------------- proposals (§131/§132)
def _proposal_service(gate):
    from app.services.proposal_service import ProposalService

    return ProposalService(repository=None, lead_service=None, tenant_admin_service=None, tenant_user_service=None,
                           billing_catalog=gate.catalog, rate_engine=gate.rate_engine, billing_gate=gate)


@pytest.mark.parametrize(
    ("operational", "marketing", "code", "price", "estimate"),
    [
        ("800", "Sim, até 100/mês", "PLAN_INICIAL_2026_10", Decimal("197"), Decimal("55.00")),
        ("2500", "Até 500/mês", "PLAN_ESSENCIAL_2026_10", Decimal("297"), Decimal("275.00")),
        ("5000", "Não", "PLAN_CRESCIMENTO_2026_10", Decimal("497"), Decimal("0.00")),
        ("10000", "Não", "PLAN_PROFISSIONAL_2026_10", Decimal("897"), Decimal("0.00")),
        ("20000", "Não", "PLAN_EMPRESARIAL_2026_10", None, Decimal("0.00")),
    ],
)
def test_proposal_recommendation_smoke(gate, operational, marketing, code, price, estimate):
    rec = _proposal_service(gate).recommend(operational_answer=operational, marketing_answer=marketing,
                                            billing_mode=SP)
    assert rec.plan_code == code
    assert rec.monthly_value == price
    assert rec.marketing_estimate == estimate
    text = "\n".join(rec.included_items).lower()
    assert "ilimitad" not in text and "meta inclusa" not in text
    if price is None:
        assert rec.is_custom and rec.margin is None


def test_proposal_margin_check_red_yellow(gate):
    service = _proposal_service(gate)
    red = service.simulate_margin(price=Decimal("10"), operational_units=1000, billing_mode=SP,
                                  plan_code="PLAN_INICIAL_2026_10", discount_reason="qualquer motivo")
    assert red["status"] == "red" and red["discount"]["allowed"] is False
    yellow = service.simulate_margin(price=Decimal("41.18"), operational_units=1000, billing_mode=SP,
                                     plan_code="PLAN_INICIAL_2026_10")
    assert yellow["status"] == "yellow" and yellow["discount"]["code"] == "reason_required"
    approved = service.simulate_margin(price=Decimal("41.18"), operational_units=1000, billing_mode=SP,
                                       plan_code="PLAN_INICIAL_2026_10", discount_reason="piloto aprovado pela diretoria")
    assert approved["discount"]["allowed"] is True
    catalog = service.simulate_margin(price=Decimal("197"), operational_units=1000, billing_mode=SP,
                                      plan_code="PLAN_INICIAL_2026_10")
    assert catalog["status"] == "partial"
    assert catalog["status_label"] == "Estimativa parcial"


def test_plan_assignment_margin_guard(gate):
    from app.services.proposal_service import MarginBlocked

    service = _proposal_service(gate)
    with pytest.raises(MarginBlocked):
        service.assert_plan_margin(plan_code="PLAN_PROFISSIONAL_2026_10", monthly_price=Decimal("10"),
                                   operational_allowance=12000, billing_mode=SP, reason="cliente pediu desconto",
                                   action="test", actor="t")
    with pytest.raises(MarginBlocked):
        service.assert_plan_margin(plan_code="PLAN_INICIAL_2026_10", monthly_price=Decimal("41.18"),
                                   operational_allowance=1000, billing_mode=SP, reason=None, action="test", actor="t")
    ok = service.assert_plan_margin(plan_code="PLAN_INICIAL_2026_10", monthly_price=Decimal("41.18"),
                                    operational_allowance=1000, billing_mode=SP, reason="piloto aprovado",
                                    action="test", actor="t")
    assert ok["status"] == "yellow" and ok["discount"]["allowed"] is True
    with pytest.raises(ValueError, match="sob consulta"):
        service.assert_plan_margin(plan_code="PLAN_EMPRESARIAL_2026_10", monthly_price=None, operational_allowance=None,
                                   billing_mode=SP, reason="x" * 10, action="test", actor="t")
    catalog = service.assert_plan_margin(plan_code="PLAN_INICIAL_2026_10", monthly_price=None, operational_allowance=None,
                                         billing_mode=CD, reason=None, action="test", actor="t")
    assert catalog["discount"]["allowed"] is True


def test_billing_events_are_logged_without_content(db, gate, caplog):
    import logging

    key, _pk = _plan_tenant(db, gate)
    with caplog.at_level(logging.INFO, logger="app.services.billing_gate"):
        d = _reserve(gate, key)
        gate.mark_accepted(key, d.reservation_id, "wamid.LOG1")
        gate.apply_status(key, "wamid.LOG1", "delivered")
        f = _reserve(gate, key)
        gate.release(key, f.reservation_id, reason="send_failed")
    text = caplog.text
    for event in ("billing.reserve", "billing.rate_selected", "billing.commit", "billing.release"):
        assert event in text
    assert "Authorization" not in text and "password" not in text.lower()


# ----------------------------------------------------------------- reconciliation
def test_stale_reservation_goes_to_reconciliation_not_auto_release(db, gate):
    key, pk = _plan_tenant(db, gate)
    decision = _reserve(gate, key)
    db.execute("UPDATE billing_reservations SET created_at=%s WHERE id=%s",
               (datetime.utcnow() - timedelta(days=3), decision.reservation_id))
    assert gate.mark_stale_pending(older_than_minutes=60) >= 1
    res = db.fetch_one("SELECT status FROM billing_reservations WHERE id=%s", (decision.reservation_id,))
    assert res["status"] == "pending_reconciliation"
    assert _bucket_totals(db, pk, "operational")["reserved"] == 1
    out = gate.resolve_reconciliation(pk, decision.reservation_id, action="release", actor_id="admin", reason="sem status Meta")
    assert out["after"] == "released"
    assert _bucket_totals(db, pk, "operational")["available"] == 1000


def test_rate_card_versions_are_insert_only(db, gate):
    with pytest.raises(ValueError, match="nova vigência"):
        gate.rate_engine.create_version({
            "version_code": "RATE_BR_DUP", "market": "BR", "currency": "BRL", "effective_from": "2026-10-01",
            "rates": [{"category": "MARKETING", "unit_price": "0.40"}],
        })
    future = f"2099-{uuid.uuid4().int % 12 + 1:02d}-{uuid.uuid4().int % 28 + 1:02d}"
    if db.fetch_one("SELECT id FROM meta_rate_cards WHERE effective_from=%s AND category='MARKETING'", (future,)):
        pytest.skip("future date collision in scratch DB")
    created = gate.rate_engine.create_version({
        "version_code": "RATE_BR_TEST_FUTURE", "market": "BR", "currency": "BRL", "effective_from": future,
        "rates": [{"category": "MARKETING", "unit_price": "0.40"}],
    })
    assert len(created) == 1
    current = gate.rate_engine.resolve("MARKETING", market="BR")
    assert current.unit_price == Decimal("0.321700")
