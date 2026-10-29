"""Isolated Stripe TEST tenant + Inicial checkout (run inside backend-api). Never prints secrets.

    ... exec -T backend-api python scripts/stripe_test_tenant.py setup     # tenant awaiting payment + checkout URL
    ... exec -T backend-api python scripts/stripe_test_tenant.py status    # subscription / allowance / invoices
    ... exec -T backend-api python scripts/stripe_test_tenant.py checkout  # new checkout URL (e.g. after a decline)
"""
import asyncio
import secrets
import sys

from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.services.billing_catalog_service import BillingCatalogService
from app.services.billing_gate import BillingGate
from app.services.billing_service import BillingService
from app.services.meta_rate_engine import MetaRateEngine
from app.services.subscription_service import SubscriptionService
from app.repositories.message_repository import MySQLMessageRepository
from app.services.tenant_admin_service import TenantAdminService
from app.services.tenant_settings_service import TenantSettingsService

TENANT = sys.argv[2] if len(sys.argv) > 2 else "stripe-teste-inicial"
PLAN = "PLAN_INICIAL_2026_10"

db = MySQLDatabase(settings.DATABASE_URL)
gate = BillingGate(db, MetaRateEngine(db), BillingCatalogService(db))
billing = BillingService(database=db, settings=settings)
billing.billing_gate = gate


async def setup() -> None:
    if db.get_tenant_record(TENANT) is None:
        admin = TenantAdminService(database=db, tenant_settings_service=TenantSettingsService(db),
                                   subscription_service=SubscriptionService(db, MySQLMessageRepository(db), settings),
                                   settings=settings, flow_service=None, flow_catalog_service=None)
        admin.bootstrap_default_flows = lambda tenant_id: asyncio.sleep(0)  # no flows: this tenant never answers
        await admin.create_tenant(tenant_id=TENANT, name=f"[TESTE STRIPE] {TENANT}", email=f"{TENANT}@meuatendeai.com.br",
                                  owner_name="Teste Stripe", owner_email=f"{TENANT}@meuatendeai.com.br",
                                  owner_password=secrets.token_urlsafe(16), plan="inicial", subscription_status="inactive")
        gate.configure_plan(gate.tenant_pk(TENANT), plan_code=PLAN, actor_id=None, require_paid=True)
        print("tenant criado:", TENANT, "(assinatura inactive, plano V2 Inicial sem franquia até o pagamento)")
    await status()
    await checkout()


async def checkout() -> None:
    session = await billing.create_checkout_session(tenant_id=TENANT, tenant_name=f"[TESTE STRIPE] {TENANT}",
                                                    customer_email=f"{TENANT}@meuatendeai.com.br",
                                                    customer_name=f"[TESTE STRIPE] {TENANT}", plan=PLAN)
    print("checkout:", session.checkout_url)


async def status() -> None:
    pk = gate.tenant_pk(TENANT)
    sub = db.fetch_one("SELECT plan, status FROM subscriptions WHERE tenant_id=%s", (pk,))
    cust = db.fetch_one("SELECT status, provider_subscription_id IS NOT NULL AS has_sub FROM billing_customers "
                        "WHERE tenant_id=%s", (pk,)) or {}
    op = gate.summary(TENANT)["operational"]
    grants = db.fetch_all("SELECT units, idempotency_key AS grant_key FROM billing_ledger WHERE tenant_id=%s "
                          "AND entry_type='GRANT' ORDER BY id", (pk,))
    invoices = db.fetch_all("SELECT status, amount_paid, amount_due FROM billing_invoices WHERE tenant_id=%s "
                            "ORDER BY id", (pk,))
    print("assinatura:", sub, "| cliente Stripe:", cust)
    print("franquia: disponível", op["total_available"], "| plano", op["plan_available"], "| bloqueado", op["blocked"])
    print("concessões:", [(int(g["units"]), g["grant_key"]) for g in grants])
    print("faturas:", [(i["status"], int(i["amount_paid"] or 0), int(i["amount_due"] or 0)) for i in invoices])


asyncio.run({"setup": setup, "status": status, "checkout": checkout}[sys.argv[1] if len(sys.argv) > 1 else "status"]())
