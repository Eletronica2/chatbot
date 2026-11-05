"""Commercial flow: Stripe Checkout sells Catalog V2 plans; only payment activates the allowance; LIVE is locked."""
import asyncio
import os
import uuid
from datetime import datetime, timedelta
from types import SimpleNamespace

import pytest

from app.services.billing_service import BillingService

DB_URL = os.environ.get("BILLING_V2_TEST_DATABASE_URL", "").strip()

INICIAL = {"code": "PLAN_INICIAL_2026_10", "kind": "plan", "status": "active", "label": "Inicial",
           "price": "197.000000", "operational_units": 1000, "plan_key": "inicial"}


def _run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


def _service(key="sk_test_x", allow_live=False):
    settings = SimpleNamespace(
        STRIPE_SECRET_KEY=key, STRIPE_ALLOW_LIVE=allow_live, BILLING_PROVIDER="stripe",
        BILLING_SUCCESS_URL="https://painel/ok", BILLING_CANCEL_URL="https://painel/cancel",
        STRIPE_PRICE_STARTER="", STRIPE_PRICE_GROWTH="", STRIPE_PRICE_PRO="", STRIPE_PRICE_ENTERPRISE="",
    )
    service = BillingService(database=SimpleNamespace(), settings=settings)
    service.billing_gate = SimpleNamespace(catalog=SimpleNamespace(
        get_item=lambda code: INICIAL if code == INICIAL["code"] else None, list_items=lambda: [INICIAL]))
    sent = {}

    async def stripe_post(path, form):
        sent.update(form)
        return {"id": "cs_test_1", "url": "https://checkout.stripe.test/1"}

    async def no_snapshot(tenant_id):
        return None

    async def customer(**kwargs):
        return "cus_1"

    async def touch(**kwargs):
        return None

    service._stripe_post = stripe_post
    service.get_customer_snapshot = no_snapshot
    service._find_or_create_customer = customer
    service._touch_customer_checkout_url = touch
    return service, sent


def _checkout(service, plan="PLAN_INICIAL_2026_10"):
    return _run(service.create_checkout_session(tenant_id="acme", tenant_name="Acme", customer_email="a@acme.com",
                                                customer_name="Acme", plan=plan))


def test_checkout_sells_the_catalog_v2_plan_at_catalog_price():
    service, sent = _service()
    checkout = _checkout(service)
    assert checkout.plan == "PLAN_INICIAL_2026_10" and checkout.checkout_url
    assert sent["mode"] == "subscription"
    assert sent["line_items[0][price_data][unit_amount]"] == "19700"
    assert sent["line_items[0][price_data][recurring][interval]"] == "month"
    assert sent["subscription_data[metadata][plan_code]"] == "PLAN_INICIAL_2026_10"
    assert service.v2_plans() == [{"code": "PLAN_INICIAL_2026_10", "label": "Inicial", "price": "197.000000",
                                   "operational_units": 1000}]


def test_live_key_never_charges_without_owner_authorization():
    service, sent = _service(key="sk_live_x")
    with pytest.raises(ValueError, match="LIVE"):
        _checkout(service)
    assert not sent and not service.stripe_charging_allowed
    pending = _run(service.create_topup_checkout(tenant_id="acme", purchase={"total_amount": "49.90", "id": "p"}))
    assert pending["checkout_url"] is None
    authorized, _ = _service(key="sk_live_x", allow_live=True)
    assert authorized.stripe_charging_allowed and _checkout(authorized).checkout_url


def test_second_subscription_is_refused():
    service, _ = _service()

    async def active(tenant_id):
        return SimpleNamespace(provider_subscription_id="sub_1", status="active")

    service.get_customer_snapshot = active
    with pytest.raises(ValueError, match="já tem uma assinatura"):
        _checkout(service)


# ── payment lifecycle against a disposable MySQL ─────────────────────────────

needs_db = pytest.mark.skipif(not DB_URL, reason="BILLING_V2_TEST_DATABASE_URL not set")


@pytest.fixture(scope="module")
def stack():
    from app.db.mysql import MySQLDatabase
    from app.services.billing_catalog_service import BillingCatalogService
    from app.services.billing_gate import BillingGate
    from app.services.meta_rate_engine import MetaRateEngine

    db = MySQLDatabase(DB_URL)
    db.bootstrap(default_tenant_key="default", default_tenant_name="Default", default_tenant_email="d@example.com")
    gate = BillingGate(db, MetaRateEngine(db), BillingCatalogService(db))
    settings = SimpleNamespace(STRIPE_SECRET_KEY="sk_test_x", STRIPE_ALLOW_LIVE=False, BILLING_GRACE_DAYS=3,
                               STRIPE_DEFAULT_CURRENCY="brl", STRIPE_PRICE_STARTER="", STRIPE_PRICE_GROWTH="",
                               STRIPE_PRICE_PRO="", STRIPE_PRICE_ENTERPRISE="")
    billing = BillingService(database=db, settings=settings)
    billing.billing_gate = gate
    return db, gate, billing


def _sold_tenant(db, gate):
    """What lead conversion now creates: V2 plan assigned, subscription awaiting the first payment."""
    key = f"sold-{uuid.uuid4().hex[:10]}"
    pk = db.insert("INSERT INTO tenants (external_key, name, email, plan, status) VALUES (%s, %s, %s, 'inicial', 'active')",
                   (key, key, f"{key}@example.com"))
    db.execute("INSERT INTO subscriptions (tenant_id, plan, status, renewal_date) VALUES (%s, 'inicial', 'inactive', %s)",
               (pk, datetime.utcnow() + timedelta(days=30)))
    result = gate.configure_plan(pk, plan_code="PLAN_INICIAL_2026_10", actor_id=None, require_paid=True)
    return key, pk, result


def _available(gate, key):
    return gate.summary(key)["operational"]["total_available"]


@needs_db
def test_sold_customer_has_no_allowance_until_paid_then_payment_activates_it(stack):
    db, gate, billing = stack
    key, pk, result = _sold_tenant(db, gate)
    assert result["grant"] == {"created": False, "reason": "subscription_not_paid"}
    assert _available(gate, key) == 0
    assert gate.preflight(key, category="SERVICE").allowed is False  # auto-replies blocked before paying
    session = {"metadata": {"tenant_id": key, "plan_code": "PLAN_INICIAL_2026_10"}, "customer": f"cus_{pk}",
               "subscription": f"sub_{pk}", "payment_status": "paid"}
    _run(billing._handle_checkout_completed(session))
    assert _available(gate, key) == 1000 and gate.preflight(key, category="SERVICE").allowed is True
    status = db.fetch_one("SELECT status FROM subscriptions WHERE tenant_id=%s", (pk,))["status"]
    assert status == "active"
    invoice = {"id": f"in_{pk}", "customer": f"cus_{pk}", "subscription": f"sub_{pk}", "amount_due": 19700,
               "amount_paid": 19700, "subscription_details": {"metadata": {"plan_code": "PLAN_INICIAL_2026_10"}},
               "lines": {"data": [{"period": {"end": int((datetime.utcnow() + timedelta(days=30)).timestamp())}}]}}
    _run(billing._handle_invoice_event(invoice, event_type="invoice.paid"))
    _run(billing._handle_invoice_event(invoice, event_type="invoice.paid"))  # webhook retried
    assert _available(gate, key) == 1000  # same cycle: never granted twice


@needs_db
def test_unpaid_checkout_does_not_activate(stack):
    db, gate, billing = stack
    key, pk, _ = _sold_tenant(db, gate)
    _run(billing._handle_checkout_completed({"metadata": {"tenant_id": key, "plan_code": "PLAN_INICIAL_2026_10"},
                                             "customer": f"cus_{pk}", "payment_status": "unpaid"}))
    assert _available(gate, key) == 0


@needs_db
@pytest.mark.parametrize("event", ["invoice.payment_failed", "customer.subscription.deleted"])
def test_past_due_or_canceled_gets_no_next_cycle(stack, event):
    db, gate, billing = stack
    key, pk, _ = _sold_tenant(db, gate)
    _run(billing._handle_checkout_completed({"metadata": {"tenant_id": key, "plan_code": "PLAN_INICIAL_2026_10"},
                                             "customer": f"cus_{pk}", "subscription": f"sub_{pk}",
                                             "payment_status": "paid"}))
    if event == "invoice.payment_failed":
        _run(billing._handle_invoice_event({"id": f"in_f_{pk}", "customer": f"cus_{pk}", "amount_due": 19700},
                                           event_type=event))
        expected = "past_due"
    else:
        _run(billing._handle_subscription_event({"id": f"sub_{pk}", "customer": f"cus_{pk}", "status": "canceled",
                                                 "metadata": {"tenant_id": key}}))
        expected = "canceled"
    assert db.fetch_one("SELECT status FROM subscriptions WHERE tenant_id=%s", (pk,))["status"] == expected
    gate._granted_cycles.pop(pk, None)
    next_cycle = gate.ensure_cycle_grant(pk, cycle_hint=datetime.utcnow() + timedelta(days=40))
    assert next_cycle == {"created": False, "reason": "subscription_not_paid"}


# ── API 2026-09-30.endive (basil+) payload shapes and signature tolerance ────

import hashlib  # noqa: E402
import hmac  # noqa: E402
import json  # noqa: E402
import time  # noqa: E402


def test_basil_shapes_are_read():
    sub = {"id": "sub_1", "items": {"data": [{"current_period_end": 1893456000, "price": {"id": "price_x"}}]}}
    assert BillingService._subscription_period_end(sub) == 1893456000
    assert BillingService._subscription_period_end({"current_period_end": 1}) == 1
    basil = {"parent": {"subscription_details": {"subscription": "sub_1", "metadata": {"plan_code": "PLAN_X"}}}}
    assert BillingService._invoice_subscription(basil) == ("sub_1", {"plan_code": "PLAN_X"})
    legacy = {"subscription": "sub_2", "subscription_details": {"metadata": {"plan_code": "PLAN_Y"}}}
    assert BillingService._invoice_subscription(legacy) == ("sub_2", {"plan_code": "PLAN_Y"})


def _signed(service, payload: bytes, ts: int) -> str:
    sig = hmac.new(service.settings.STRIPE_WEBHOOK_SECRET.encode(), f"{ts}.{payload.decode()}".encode(),
                   hashlib.sha256).hexdigest()
    return f"t={ts},v1=deadbeef,v1={sig}"


def test_signature_accepts_fresh_and_rejects_old_or_wrong():
    service, _ = _service()
    service.settings.STRIPE_WEBHOOK_SECRET = "whsec_test"
    payload = json.dumps({"type": "ping"}).encode()
    assert service._verify_stripe_signature(payload, _signed(service, payload, int(time.time())))["type"] == "ping"
    with pytest.raises(ValueError, match="expirada"):
        service._verify_stripe_signature(payload, _signed(service, payload, int(time.time()) - 3600))
    with pytest.raises(ValueError, match="invalida"):
        service._verify_stripe_signature(payload, f"t={int(time.time())},v1=deadbeef")


@needs_db
def test_basil_invoice_paid_activates_plan_without_checkout_event(stack):
    db, gate, billing = stack
    key, pk, _ = _sold_tenant(db, gate)
    db.execute("INSERT INTO billing_customers (tenant_id, provider, provider_customer_id, status) "
               "VALUES (%s, 'stripe', %s, 'inactive')", (pk, f"cus_b_{pk}"))
    invoice = {"id": f"in_b_{pk}", "customer": f"cus_b_{pk}", "amount_due": 19700, "amount_paid": 19700,
               "parent": {"type": "subscription_details", "subscription_details": {
                   "subscription": f"sub_b_{pk}", "metadata": {"plan_code": "PLAN_INICIAL_2026_10", "tenant_id": key}}},
               "lines": {"data": [{"period": {"end": int((datetime.utcnow() + timedelta(days=30)).timestamp())}}]}}
    _run(billing._handle_invoice_event(invoice, event_type="invoice.paid"))
    assert _available(gate, key) == 1000
    row = db.fetch_one("SELECT provider_subscription_id FROM billing_invoices WHERE provider_invoice_id=%s",
                       (f"in_b_{pk}",))
    assert row["provider_subscription_id"] == f"sub_b_{pk}"


# ── TEST/LIVE separation ──────────────────────────────────────────────────────

@pytest.mark.parametrize("key,event_livemode", [("sk_test_x", True), ("rk_live_x", False), ("sk_live_x", False)])
def test_webhook_from_the_other_mode_is_ignored(key, event_livemode):
    service, _ = _service(key=key)
    service.settings.STRIPE_WEBHOOK_SECRET = "whsec_test"
    payload = json.dumps({"type": "invoice.paid", "livemode": event_livemode, "data": {"object": {"customer": "cus_x"}}}).encode()
    result = _run(service.handle_webhook(payload=payload, signature=_signed(service, payload, int(time.time()))))
    assert result["ignored"] == "mode_mismatch"


def test_rk_live_is_a_live_key_locked_by_default():
    service, _ = _service(key="rk_live_x")
    assert service.stripe_live_key and service.stripe_mode_flag == 1 and not service.stripe_charging_allowed


@needs_db
def test_test_customer_is_invisible_in_live_and_replaced_by_live_customer(stack):
    db, gate, _ = stack
    key, pk, _ = _sold_tenant(db, gate)
    db.execute("INSERT INTO billing_customers (tenant_id, provider, provider_customer_id, provider_subscription_id, status) "
               "VALUES (%s, 'stripe', %s, %s, 'active')", (pk, f"cus_t_{pk}", f"sub_t_{pk}"))

    def service(secret):
        settings = SimpleNamespace(STRIPE_SECRET_KEY=secret, STRIPE_ALLOW_LIVE=False)
        return BillingService(database=db, settings=settings)

    live, test = service("sk_live_x"), service("sk_test_x")
    assert _run(test.get_customer_snapshot(key)).provider_customer_id == f"cus_t_{pk}"
    assert _run(live.get_customer_snapshot(key)) is None  # no reuse, no "already subscribed" block from TEST
    _run(live._upsert_customer_record(tenant_id=key, provider_customer_id=f"cus_l_{pk}", provider_subscription_id=None,
                                      provider_price_id=None, status="inactive", current_period_end=None))
    assert _run(live.get_customer_snapshot(key)).provider_customer_id == f"cus_l_{pk}"
    assert _run(test.get_customer_snapshot(key)) is None
