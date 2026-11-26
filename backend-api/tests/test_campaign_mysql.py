"""Campaign integration tests (MySQL). Uses BILLING_V2_TEST_DATABASE_URL or CAMPAIGN_TEST_DATABASE_URL."""
from __future__ import annotations

import os
import uuid
from datetime import datetime, timedelta

import pytest

DB_URL = (
    os.environ.get("CAMPAIGN_TEST_DATABASE_URL", "").strip()
    or os.environ.get("BILLING_V2_TEST_DATABASE_URL", "").strip()
)
pytestmark = pytest.mark.skipif(not DB_URL, reason="CAMPAIGN_TEST_DATABASE_URL not set")

if DB_URL:
    from app.db.mysql import MySQLDatabase
    from app.repositories.campaign_repository import CampaignRepository
    from app.services.campaign_status import should_promote


@pytest.fixture(scope="module")
def db():
    database = MySQLDatabase(DB_URL)
    database.bootstrap(
        default_tenant_key="default",
        default_tenant_name="Default",
        default_tenant_email="default@example.com",
    )
    return database


@pytest.fixture()
def repo(db):
    return CampaignRepository(db)


def _tenant(db) -> tuple[str, int]:
    key = f"camp-{uuid.uuid4().hex[:10]}"
    pk = db.insert(
        "INSERT INTO tenants (external_key, name, email, plan, status) VALUES (%s, %s, %s, 'starter', 'active')",
        (key, f"Camp {key}", f"{key}@example.com"),
    )
    db.execute(
        "INSERT INTO subscriptions (tenant_id, plan, status, renewal_date, monthly_message_limit) VALUES (%s,'starter','active',%s,5000)",
        (pk, datetime.utcnow() + timedelta(days=30)),
    )
    return key, pk


@pytest.mark.asyncio
async def test_reclaim_marks_uncertain_without_wamid(repo, db):
    key, _pk = _tenant(db)
    camp = await repo.create_campaign(
        tenant_id=key,
        payload={"name": "t", "template_name": "tpl", "template_category": "UTILITY"},
    )
    cid = int(camp["id"])
    await repo.replace_recipients(
        tenant_id=key,
        campaign_id=cid,
        rows=[
            {
                "row_number": 1,
                "phone": "5534999999999",
                "body_params": {},
                "consent_ok": True,
                "errors": [],
                "idempotency_key": f"k:{uuid.uuid4().hex}",
            }
        ],
    )
    recs = await repo.list_recipients(tenant_id=key, campaign_id=cid)
    rid = int(recs[0]["id"])
    await repo.update_recipient(key, rid, {"status": "sending"})
    db.execute(
        "UPDATE whatsapp_campaign_recipients SET updated_at=%s WHERE id=%s",
        (datetime.utcnow() - timedelta(minutes=20), rid),
    )
    n = await repo.reclaim_stale_sending(tenant_id=key, campaign_id=cid, older_minutes=15)
    assert n >= 1
    row = db.fetch_one("SELECT status, error_message FROM whatsapp_campaign_recipients WHERE id=%s", (rid,))
    assert row["status"] == "uncertain"
    assert row["error_message"]


@pytest.mark.asyncio
async def test_reclaim_preserves_wamid_as_sent(repo, db):
    key, _pk = _tenant(db)
    camp = await repo.create_campaign(
        tenant_id=key,
        payload={"name": "w", "template_name": "tpl", "template_category": "UTILITY"},
    )
    cid = int(camp["id"])
    wamid = f"wamid.{uuid.uuid4().hex}"
    await repo.replace_recipients(
        tenant_id=key,
        campaign_id=cid,
        rows=[
            {
                "row_number": 1,
                "phone": "5534222222222",
                "body_params": {},
                "consent_ok": True,
                "errors": [],
                "idempotency_key": f"k:{uuid.uuid4().hex}",
            }
        ],
    )
    recs = await repo.list_recipients(tenant_id=key, campaign_id=cid)
    rid = int(recs[0]["id"])
    await repo.update_recipient(
        key, rid, {"status": "sending", "provider_message_id": wamid}
    )
    db.execute(
        "UPDATE whatsapp_campaign_recipients SET updated_at=%s WHERE id=%s",
        (datetime.utcnow() - timedelta(minutes=20), rid),
    )
    await repo.reclaim_stale_sending(tenant_id=key, campaign_id=cid, older_minutes=15)
    row = db.fetch_one(
        "SELECT status, provider_message_id FROM whatsapp_campaign_recipients WHERE id=%s",
        (rid,),
    )
    assert row["status"] == "sent"
    assert row["provider_message_id"] == wamid


@pytest.mark.asyncio
async def test_uncertain_separate_from_failed(repo, db):
    key, _pk = _tenant(db)
    camp = await repo.create_campaign(
        tenant_id=key,
        payload={"name": "c", "template_name": "tpl", "template_category": "UTILITY"},
    )
    cid = int(camp["id"])
    await repo.replace_recipients(
        tenant_id=key,
        campaign_id=cid,
        rows=[
            {
                "row_number": 1,
                "phone": "5534333333333",
                "body_params": {},
                "consent_ok": True,
                "errors": [],
                "idempotency_key": f"k:{uuid.uuid4().hex}",
            },
            {
                "row_number": 2,
                "phone": "5534444444444",
                "body_params": {},
                "consent_ok": True,
                "errors": [],
                "idempotency_key": f"k:{uuid.uuid4().hex}",
            },
        ],
    )
    recs = await repo.list_recipients(tenant_id=key, campaign_id=cid)
    await repo.update_recipient(key, int(recs[0]["id"]), {"status": "uncertain"})
    await repo.update_recipient(key, int(recs[1]["id"]), {"status": "failed"})
    await repo.refresh_campaign_counters(key, cid)
    row = db.fetch_one("SELECT failed_count, uncertain_count FROM whatsapp_campaigns WHERE id=%s", (cid,))
    assert int(row["uncertain_count"]) == 1
    assert int(row["failed_count"]) == 1


@pytest.mark.asyncio
async def test_webhook_idempotency_and_tenant_isolation(repo, db):
    key_a, _pk_a = _tenant(db)
    key_b, _pk_b = _tenant(db)
    camp_a = await repo.create_campaign(
        tenant_id=key_a,
        payload={"name": "a", "template_name": "t", "template_category": "UTILITY"},
    )
    await repo.replace_recipients(
        tenant_id=key_a,
        campaign_id=int(camp_a["id"]),
        rows=[
            {
                "row_number": 1,
                "phone": "5534111111111",
                "body_params": {},
                "consent_ok": True,
                "errors": [],
                "idempotency_key": f"k:{uuid.uuid4().hex}",
            }
        ],
    )
    rec = (await repo.list_recipients(tenant_id=key_a, campaign_id=int(camp_a["id"])))[0]
    wamid = f"wamid.{uuid.uuid4().hex}"
    await repo.update_recipient(key_a, int(rec["id"]), {"status": "sent", "provider_message_id": wamid})

    r1 = repo.apply_provider_status_sync(key_a, wamid, "delivered")
    r2 = repo.apply_provider_status_sync(key_a, wamid, "delivered")
    assert r1.get("applied") is True
    assert r2.get("applied") is False

    r3 = repo.apply_provider_status_sync(key_b, wamid, "delivered")
    assert r3.get("reason") == "not_campaign"

    r4 = repo.apply_provider_status_sync(key_a, wamid, "read")
    assert r4.get("applied") is True
    assert should_promote("delivered", "read")
    st = db.fetch_one(
        "SELECT status FROM whatsapp_campaign_recipients WHERE id=%s",
        (int(rec["id"]),),
    )
    assert st["status"] == "read"