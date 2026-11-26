"""Simulated template status webhook ingestion (no Meta calls)."""
from __future__ import annotations

import os
import uuid
from datetime import datetime, timedelta

import pytest

DB_URL = (
    os.environ.get("CAMPAIGN_TEST_DATABASE_URL", "").strip()
    or os.environ.get("BILLING_V2_TEST_DATABASE_URL", "").strip()
)
pytestmark = pytest.mark.skipif(not DB_URL, reason="test database URL not set")

if DB_URL:
    from app.db.mysql import MySQLDatabase
    from app.repositories.whatsapp_account_repository import WhatsAppAccountRepository
    from app.repositories.whatsapp_template_status_repository import WhatsAppTemplateStatusRepository
    from app.security.crypto import TokenCipher
    from app.services.meta_graph_service import MetaGraphService
    from app.services.whatsapp_account_service import WhatsAppAccountService
    from app.services.whatsapp_template_status_service import WhatsAppTemplateStatusService


@pytest.fixture(scope="module")
def db():
    database = MySQLDatabase(DB_URL)
    database.bootstrap(
        default_tenant_key="default",
        default_tenant_name="Default",
        default_tenant_email="default@example.com",
    )
    return database


def _tenant_with_waba(db) -> tuple[str, str]:
    key = f"tpl-{uuid.uuid4().hex[:10]}"
    pk = db.insert(
        "INSERT INTO tenants (external_key, name, email, plan, status) VALUES (%s, %s, %s, 'starter', 'active')",
        (key, f"Tpl {key}", f"{key}@example.com"),
    )
    db.execute(
        "INSERT INTO subscriptions (tenant_id, plan, status, renewal_date, monthly_message_limit) VALUES (%s,'starter','active',%s,5000)",
        (pk, datetime.utcnow() + timedelta(days=30)),
    )
    waba = f"waba{uuid.uuid4().hex[:12]}"
    db.execute(
        """
        INSERT INTO whatsapp_accounts (
            tenant_id, account_key, display_name, phone_number_id, display_phone_number, status, is_default
        ) VALUES (%s, %s, 'Test', %s, '+5500000000000', 'active', 1)
        """,
        (pk, waba, f"pn{uuid.uuid4().hex[:10]}"),
    )
    return key, waba


@pytest.mark.asyncio
async def test_template_status_webhook_idempotency_and_isolation(db):
    key_a, waba_a = _tenant_with_waba(db)
    key_b, waba_b = _tenant_with_waba(db)
    repo = WhatsAppTemplateStatusRepository(db)
    wa = WhatsAppAccountService(
        WhatsAppAccountRepository(db),
        TokenCipher("test-secret-key-32bytes-minimum!!"),
        MetaGraphService(),
    )
    svc = WhatsAppTemplateStatusService(repo, wa)

    payload = {
        "event": "APPROVED",
        "message_template_id": "9001",
        "message_template_name": "hello_test",
        "message_template_language": "pt_BR",
        "reason": "NONE",
    }
    r1 = await svc.ingest_webhook(waba_id=waba_a, entry_time=1_000_000, value=payload)
    r2 = await svc.ingest_webhook(waba_id=waba_a, entry_time=1_000_000, value=payload)
    assert r1.get("applied") is True
    assert r2.get("applied") is False

    stale = await svc.ingest_webhook(
        waba_id=waba_a,
        entry_time=999_000,
        value={**payload, "event": "REJECTED"},
    )
    assert stale.get("applied") is False

    wrong = await svc.ingest_webhook(waba_id=waba_b, entry_time=1_000_001, value=payload)
    assert wrong.get("applied") is True

    watch_a = await svc.list_watch(tenant_id=key_a, account_key=waba_a, since_unix=0)
    assert any(item["status"] == "APPROVED" for item in watch_a)
    watch_b = await svc.list_watch(tenant_id=key_b, account_key=waba_b, since_unix=0)
    assert all(item["name"] == "hello_test" for item in watch_b)
    assert watch_a[0]["name"] == watch_b[0]["name"]
    assert key_a != key_b