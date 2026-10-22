"""Rehearsal of provision_bella_massa.py against a disposable MySQL (never production).

Builds a schema with the backend bootstrap, adds tenants shaped like production, runs the provisioning
twice and checks login, RBAC, isolation and the homologation state. Prints PASS/FAIL lines only.
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import os
import subprocess
import sys
from types import SimpleNamespace

from fastapi import HTTPException

from app.api.access import capabilities_for, resolve_tenant_scope
from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.domain.auth import AuthenticatedUser
from app.repositories.message_repository import MySQLMessageRepository
from app.repositories.user_repository import UserRepository
from app.services.auth_service import AuthService
from app.services.subscription_service import SubscriptionService
from app.services.tenant_admin_service import TenantAdminService
from app.services.tenant_settings_service import TenantSettingsService

failures = 0


def check(name: str, ok: bool) -> None:
    global failures
    failures += 0 if ok else 1
    print(("PASS " if ok else "FAIL ") + name)


def snapshot_others(db: MySQLDatabase) -> str:
    rows = {
        "tenants": db.fetch_all("SELECT id, external_key, name, email, status, plan, updated_at FROM tenants "
                                "WHERE external_key <> 'pizzaria_bella_massa' ORDER BY id"),
        "users": db.fetch_all("SELECT id, tenant_id, email, role, status, password_hash, updated_at FROM users "
                              "WHERE email <> %s ORDER BY id", (settings.BOOTSTRAP_PIZZARIA_ADMIN_EMAIL,)),
        "settings": db.fetch_all("SELECT * FROM tenant_settings WHERE tenant_id IN "
                                 "(SELECT id FROM tenants WHERE external_key <> 'pizzaria_bella_massa') ORDER BY id"),
        "subs": db.fetch_all("SELECT * FROM subscriptions WHERE tenant_id IN "
                             "(SELECT id FROM tenants WHERE external_key <> 'pizzaria_bella_massa') ORDER BY id"),
    }
    return hashlib.sha256(json.dumps(rows, default=str, sort_keys=True).encode()).hexdigest()


def run_script(mode: str) -> dict:
    out = subprocess.run([sys.executable, "scripts/provision_bella_massa.py", mode, os.environ["EXPECTED_PW_SHA256"]],
                         capture_output=True, text=True)
    return {"code": out.returncode, **json.loads(out.stdout)}


async def main() -> None:
    db = MySQLDatabase(settings.DATABASE_URL)
    db.bootstrap(default_tenant_key="default", default_tenant_name="Operacao SaaS", default_tenant_email="operacao@chatbot.local")
    users = UserRepository(db)
    auth = AuthService(users, settings)
    await auth.ensure_default_user()
    ts = TenantSettingsService(db)
    subs = SubscriptionService(db, MySQLMessageRepository(db), settings)
    admin = TenantAdminService(database=db, tenant_settings_service=ts, subscription_service=subs, settings=settings)
    if db.get_tenant_record("teste_empresa") is None:
        await admin.create_tenant(tenant_id="teste_empresa", name="Teste Empresa", email="owner-teste@example.invalid",
                                  owner_name="Owner Teste", owner_email="owner-teste@example.invalid",
                                  owner_password="rehearsal-only-1", plan="pro")
    before_others = snapshot_others(db)

    first_check = run_script("check")
    check("check: sem problemas e tenant ainda inexistente", first_check["code"] == 0 and first_check["before"]["tenant"] is None)
    first = run_script("apply")
    check("apply #1: provisionou tenant e owner", first["code"] == 0 and "tenant_and_owner_provisioned" in first["actions"])
    after = first["after"]
    check("tenant external_key/nome/status", after["tenant"]["external_key"] == "pizzaria_bella_massa"
          and after["tenant"]["name"] == "Bella Massa" and after["tenant"]["status"] == "active")
    check("owner com role owner no próprio tenant", after["owner"]["role"] == "owner" and after["owner"]["tenant"] == "pizzaria_bella_massa")
    check("um único usuário no tenant", len(after["users"]) == 1)
    check("assinatura trialing", after["subscription"]["status"] == "trialing")
    check("respostas automáticas off", after["settings"]["auto_reply_mode"] == "off")
    check("provider gemini e IA local desligada", after["settings"]["ai_provider"] == "gemini" and not after["settings"]["local_ai_enabled"])
    check("sem plano Billing V2 nem buckets", after["billing_v2_config"] is None and after["billing_buckets"] == 0)
    check("nenhuma conta WhatsApp", after["whatsapp_accounts"] == 0 and not after["tenant"]["has_whatsapp_token"]
          and after["tenant"]["whatsapp_phone_number"] is None)
    hash_after_first = db.fetch_one("SELECT password_hash FROM users WHERE email=%s", (settings.BOOTSTRAP_PIZZARIA_ADMIN_EMAIL,))["password_hash"]
    check("senha armazenada com hash do backend (não texto puro)",
          hash_after_first.startswith("pbkdf2_") and settings.BOOTSTRAP_PIZZARIA_ADMIN_PASSWORD not in hash_after_first)

    second = run_script("apply")
    check("apply #2 idempotente (nenhuma ação)", second["code"] == 0 and second["actions"] == [])
    count = db.fetch_one("SELECT COUNT(*) AS n FROM tenants WHERE external_key='pizzaria_bella_massa'")["n"]
    check("sem duplicidade de tenant", count == 1)
    hash_after_second = db.fetch_one("SELECT password_hash FROM users WHERE email=%s", (settings.BOOTSTRAP_PIZZARIA_ADMIN_EMAIL,))["password_hash"]
    check("rerun não redefine a senha do owner", hash_after_first == hash_after_second)
    check("outros tenants/usuários inalterados", snapshot_others(db) == before_others)

    for bad in ({"auto_reply_mode": "sempre"}, {"auto_reply_allowlist": ["123"]}):
        try:
            await ts.update("pizzaria_bella_massa", **bad)
            check(f"validação rejeita {list(bad)[0]} inválido", False)
        except ValueError:
            check(f"validação rejeita {list(bad)[0]} inválido", True)
    saved = await ts.update("pizzaria_bella_massa", auto_reply_allowlist=["+55 (47) 90000-0000"])
    check("allowlist persiste normalizada e modo continua off",
          saved.auto_reply_allowlist == ["5547900000000"] and saved.auto_reply_mode == "off"
          and saved.auto_reply_block_reason("5547900000000") == "auto_reply_disabled")
    await ts.update("pizzaria_bella_massa", auto_reply_allowlist=[])
    check("allowlist pode ser esvaziada", (await ts.get_or_create("pizzaria_bella_massa")).auto_reply_allowlist == [])
    check("outros tenants continuam com auto_reply on",
          (await ts.get_or_create("teste_empresa")).auto_reply_mode == "on")

    login = await auth.login(email=settings.BOOTSTRAP_PIZZARIA_ADMIN_EMAIL, password=settings.BOOTSTRAP_PIZZARIA_ADMIN_PASSWORD)
    check("login com a credencial documentada", login is not None and login.user.role == "owner")
    check("token aponta para o tenant Bella Massa", login is not None and login.user.tenant_id == "pizzaria_bella_massa")
    check("login com senha errada falha", await auth.login(email=settings.BOOTSTRAP_PIZZARIA_ADMIN_EMAIL, password="errada-123") is None)

    owner = AuthenticatedUser(user_id=login.user.user_id, tenant_id="pizzaria_bella_massa",
                              email=login.user.email, display_name="x", role="owner", status="active")
    request = SimpleNamespace(headers={}, query_params={}, state=SimpleNamespace())
    check("owner acessa o próprio tenant", resolve_tenant_scope(owner, request, "pizzaria_bella_massa") == "pizzaria_bella_massa")
    try:
        resolve_tenant_scope(owner, request, "teste_empresa")
        check("owner NÃO acessa outro tenant", False)
    except HTTPException as exc:
        check("owner NÃO acessa outro tenant", exc.status_code in (403, 404))
    caps = capabilities_for(owner)
    check("owner não acessa backoffice (não é superadmin)", caps.get("canAccessBackoffice") is False)
    check("owner pode gerenciar WhatsApp e automações do tenant",
          caps.get("canManageWhatsApp") is True and caps.get("canManageAutomations") is True)
    superadmin = AuthenticatedUser(user_id="1", tenant_id="default", email="sa@example.invalid", display_name="sa",
                                   role="superadmin", status="active")
    check("superadmin continua acessando Bella Massa", resolve_tenant_scope(superadmin, request, "pizzaria_bella_massa") == "pizzaria_bella_massa")
    print(json.dumps({"capabilities_owner": caps}, ensure_ascii=False))
    print(f"RESULT failures={failures}")


if __name__ == "__main__":
    asyncio.run(main())
    sys.exit(1 if failures else 0)
