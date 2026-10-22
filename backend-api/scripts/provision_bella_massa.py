"""Create (or verify) the Bella Massa homologation tenant through the backend's own provisioning service.

Usage, inside the backend-api container:
    python scripts/provision_bella_massa.py check <sha256-of-expected-owner-password>
    python scripts/provision_bella_massa.py apply <sha256-of-expected-owner-password>

The owner password is the backend's BOOTSTRAP_PIZZARIA_ADMIN_PASSWORD (the one documented for homologation);
it is never printed. The hash argument only proves the container holds the documented value.

What "apply" guarantees:
- tenant external_key pizzaria_bella_massa exists once (unique key), owner user is role owner of that tenant only;
- an existing owner is never moved from another tenant and an existing Bella Massa owner is not reset;
- automatic replies OFF (inbound goes to a human), AI provider gemini with local AI disabled;
- subscription "trialing" on the default plan; no Billing V2 plan, no grants, no Stripe objects;
- no WhatsApp account is created (that happens only through Embedded Signup).
"""
from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import sys

from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.repositories.message_repository import MySQLMessageRepository
from app.services.admin_audit_service import AdminAuditService
from app.services.subscription_service import SubscriptionService
from app.services.tenant_admin_service import TenantAdminService
from app.services.tenant_settings_service import TenantSettingsService

TENANT_KEY = "pizzaria_bella_massa"
TENANT_NAME = "Bella Massa"


def state(db: MySQLDatabase) -> dict:
    tenant = db.fetch_one(
        "SELECT id, external_key, name, email, status, plan, whatsapp_phone_number, "
        "(whatsapp_token IS NOT NULL) AS has_whatsapp_token FROM tenants WHERE external_key=%s",
        (TENANT_KEY,),
    )
    owner = db.fetch_one(
        "SELECT u.id, u.email, u.role, u.status, t.external_key AS tenant FROM users u "
        "JOIN tenants t ON t.id=u.tenant_id WHERE u.email=%s",
        (settings.BOOTSTRAP_PIZZARIA_ADMIN_EMAIL.strip().lower(),),
    )
    email_owner = db.fetch_one(
        "SELECT external_key FROM tenants WHERE email=%s", (settings.BOOTSTRAP_PIZZARIA_EMAIL.strip().lower(),)
    )
    out = {"tenant": tenant, "owner": owner, "tenant_email_used_by": (email_owner or {}).get("external_key")}
    if tenant:
        pk = tenant["id"]
        out["users"] = db.fetch_all("SELECT id, email, role, status FROM users WHERE tenant_id=%s", (pk,))
        out["subscription"] = db.fetch_one(
            "SELECT plan, status, renewal_date, monthly_message_limit FROM subscriptions WHERE tenant_id=%s", (pk,)
        )
        out["settings"] = db.fetch_one(
            "SELECT ai_enabled, ai_provider, local_ai_enabled, auto_reply_mode, "
            "JSON_LENGTH(auto_reply_allowlist) AS allowlist_count FROM tenant_settings WHERE tenant_id=%s", (pk,)
        )
        out["billing_v2_config"] = db.fetch_one(
            "SELECT billing_mode, plan_code, operational_allowance FROM tenant_billing_config WHERE tenant_id=%s", (pk,)
        )
        out["billing_buckets"] = db.fetch_one(
            "SELECT COUNT(*) AS n FROM billing_entitlement_buckets WHERE tenant_id=%s", (pk,)
        )["n"]
        out["whatsapp_accounts"] = db.fetch_one("SELECT COUNT(*) AS n FROM whatsapp_accounts WHERE tenant_id=%s", (pk,))["n"]
    return out


def preconditions(snapshot: dict, expected_password_sha256: str) -> list[str]:
    problems = []
    actual = hashlib.sha256(settings.BOOTSTRAP_PIZZARIA_ADMIN_PASSWORD.strip().encode("utf-8")).hexdigest()
    if not hmac.compare_digest(actual, expected_password_sha256.strip().lower()):
        problems.append("BOOTSTRAP_PIZZARIA_ADMIN_PASSWORD do container difere da credencial documentada")
    owner = snapshot["owner"]
    if owner and owner["tenant"] != TENANT_KEY:
        problems.append(f"o e-mail do owner já pertence ao tenant {owner['tenant']} (não será movido)")
    if snapshot["tenant_email_used_by"] not in (None, TENANT_KEY):
        problems.append(f"o e-mail da empresa já pertence ao tenant {snapshot['tenant_email_used_by']}")
    return problems


async def apply(db: MySQLDatabase, snapshot: dict) -> list[str]:
    actions = []
    tenant_settings = TenantSettingsService(db)
    subscriptions = SubscriptionService(db, MySQLMessageRepository(db), settings)
    admin = TenantAdminService(database=db, tenant_settings_service=tenant_settings,
                               subscription_service=subscriptions, settings=settings)
    if snapshot["tenant"] is None or snapshot["owner"] is None:
        await admin.ensure_bootstrap_tenant(
            tenant_id=TENANT_KEY,
            name=TENANT_NAME,
            email=settings.BOOTSTRAP_PIZZARIA_EMAIL,
            owner_name=settings.BOOTSTRAP_PIZZARIA_ADMIN_NAME,
            owner_email=settings.BOOTSTRAP_PIZZARIA_ADMIN_EMAIL,
            owner_password=settings.BOOTSTRAP_PIZZARIA_ADMIN_PASSWORD,
            plan="starter",
            copy_default_flows=False,
        )
        actions.append("tenant_and_owner_provisioned")
        await subscriptions.update(TENANT_KEY, status="trialing")
        actions.append("subscription_trialing")
        await AdminAuditService(db).append(
            tenant_id=TENANT_KEY, action="tenant.homolog.provision", entity_type="tenant", entity_key=TENANT_KEY,
            summary="Tenant de homologação Bella Massa provisionado (sem WhatsApp, respostas automáticas desligadas)",
            metadata={"owner_email": settings.BOOTSTRAP_PIZZARIA_ADMIN_EMAIL, "auto_reply_mode": "off",
                      "ai_provider": "gemini", "local_ai_enabled": False},
        )
    current = await tenant_settings.get_or_create(TENANT_KEY)
    if current.auto_reply_mode != "off" and current.auto_reply_mode != "allowlist":
        await tenant_settings.update(TENANT_KEY, auto_reply_mode="off")
        actions.append("auto_reply_off")
    if current.ai_provider != "gemini" or current.local_ai_enabled:
        actions.append("provider_left_unchanged_needs_review")
    return actions


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in {"check", "apply"}:
        print(__doc__)
        return 2
    db = MySQLDatabase(settings.DATABASE_URL)
    before = state(db)
    problems = preconditions(before, sys.argv[2])
    result: dict = {"mode": sys.argv[1], "problems": problems, "before": before}
    if sys.argv[1] == "apply" and not problems:
        result["actions"] = asyncio.run(apply(db, before))
        result["after"] = state(db)
    print(json.dumps(result, default=str, ensure_ascii=False, indent=1))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
