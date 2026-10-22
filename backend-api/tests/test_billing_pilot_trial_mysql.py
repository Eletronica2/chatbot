"""Billing V2 lifecycle for a homologation tenant shaped like Bella Massa (trialing, no V2 plan).

Uses a disposable MySQL (BILLING_V2_TEST_DATABASE_URL); never production.
"""
import os
import uuid

import pytest

DB_URL = os.environ.get("BILLING_V2_TEST_DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DB_URL, reason="BILLING_V2_TEST_DATABASE_URL not set")

if DB_URL:
    from app.db.mysql import MySQLDatabase
    from app.services.billing_catalog_service import BillingCatalogService
    from app.services.billing_gate import BillingGate
    from app.services.meta_rate_engine import MetaRateEngine
    from tests.test_billing_v2_mysql import _tenant


@pytest.fixture(scope="module")
def db():
    database = MySQLDatabase(DB_URL)
    database.bootstrap(default_tenant_key="default", default_tenant_name="Default", default_tenant_email="default@example.com")
    return database


@pytest.fixture()
def gate(db):
    return BillingGate(db, MetaRateEngine(db), BillingCatalogService(db))


def _reservation(db, rid):
    return db.fetch_one("SELECT status, entitlement, billing_mode, bucket_id FROM billing_reservations WHERE id=%s", (rid,))


def _ledger(db, pk):
    return [r["entry_type"] for r in db.fetch_all("SELECT entry_type FROM billing_ledger WHERE tenant_id=%s ORDER BY id", (pk,))]


def test_trial_tenant_without_plan_reply_is_tracked_not_charged(db, gate):
    key, pk = _tenant(db, subscription_status="trialing")
    assert gate.preflight(key, category="SERVICE").allowed is True
    decision = gate.reserve(key, category="SERVICE", category_source="freeform_service_reply", source_path="ai",
                            idempotency_key=f"reply:wamid.{uuid.uuid4().hex}")
    assert decision.allowed and decision.entitlement == "legacy_unmetered"
    assert _reservation(db, decision.reservation_id)["bucket_id"] is None
    gate.mark_accepted(key, decision.reservation_id, "wamid.PILOT1")
    assert gate.apply_status(key, "wamid.PILOT1", "sent")["action"] == "recorded"
    assert gate.apply_status(key, "wamid.PILOT1", "delivered")["action"] == "commit"
    assert gate.apply_status(key, "wamid.PILOT1", "delivered").get("duplicate") is True
    assert _reservation(db, decision.reservation_id)["status"] == "committed"
    assert _ledger(db, pk).count("COMMIT") == 1
    buckets = db.fetch_one("SELECT COUNT(*) AS n FROM billing_entitlement_buckets WHERE tenant_id=%s", (pk,))
    assert int(buckets["n"]) == 0
    assert db.fetch_one("SELECT COUNT(*) AS n FROM billing_invoices WHERE tenant_id=%s", (pk,))["n"] == 0


def test_trial_tenant_duplicate_reply_reserves_once(db, gate):
    key, pk = _tenant(db, subscription_status="trialing")
    idem = f"reply:wamid.{uuid.uuid4().hex}"
    first = gate.reserve(key, category="SERVICE", category_source="t", source_path="ai", idempotency_key=idem)
    second = gate.reserve(key, category="SERVICE", category_source="t", source_path="ai", idempotency_key=idem)
    assert second.duplicate is True and second.reservation_id == first.reservation_id
    assert _ledger(db, pk).count("RESERVE") == 1


def test_trial_tenant_send_failure_releases(db, gate):
    key, pk = _tenant(db, subscription_status="trialing")
    before_meta = gate.reserve(key, category="SERVICE", category_source="t", source_path="ai",
                               idempotency_key=f"reply:{uuid.uuid4().hex}")
    assert gate.release(key, before_meta.reservation_id, reason="send_failed")["changed"] is True
    assert _reservation(db, before_meta.reservation_id)["status"] == "released"
    after_meta = gate.reserve(key, category="SERVICE", category_source="t", source_path="ai",
                              idempotency_key=f"reply:{uuid.uuid4().hex}")
    gate.mark_accepted(key, after_meta.reservation_id, "wamid.PILOTFAIL")
    assert gate.apply_status(key, "wamid.PILOTFAIL", "failed", error_code="131047")["action"] == "release"
    assert "COMMIT" not in _ledger(db, pk)


def test_inbound_status_without_reservation_never_consumes(db, gate):
    key, pk = _tenant(db, subscription_status="trialing")
    assert gate.apply_status(key, "wamid.INBOUND", "delivered").get("pending") is True
    assert _ledger(db, pk) == []
