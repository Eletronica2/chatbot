"""Re-subscribe the Atende Ai app to the Bella Massa WABA webhooks (the subscribe step of the official exchange).

Used when the Embedded Signup finished on Meta's side but the popup never returned the code to the panel, so
complete_embedded_signup did not run. The stored account token (same business integration system user) is reused;
the callback URL and app webhook settings are not touched. Prints only status, never a token.

Usage inside backend-api:  python - < scripts/ia03_bella_resubscribe_waba.py
"""
import asyncio

from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.repositories.whatsapp_account_repository import WhatsAppAccountRepository
from app.security.crypto import TokenCipher
from app.services.admin_audit_service import AdminAuditService
from app.services.meta_graph_service import MetaGraphService
from app.services.whatsapp_account_service import WhatsAppAccountService

TENANT, WABA, PHONE_NUMBER_ID = "pizzaria_bella_massa", "1299741078262298", "1155710810954749"


async def main() -> None:
    db = MySQLDatabase(settings.DATABASE_URL)
    graph = MetaGraphService()
    account = await WhatsAppAccountService(WhatsAppAccountRepository(db), TokenCipher(settings.APP_SECRET_KEY),
                                           graph).resolve_for_phone_number_id(PHONE_NUMBER_ID)
    if account is None or account.account.account_key != WABA or not account.access_token:
        raise SystemExit("conta Bella não encontrada")
    await graph.subscribe_waba_webhooks(WABA, account.access_token)
    await AdminAuditService(db).append(tenant_id=TENANT, action="whatsapp_account.webhook.resubscribe",
                                       entity_type="whatsapp_account", entity_key=WABA,
                                       summary="App reassinado aos webhooks da WABA após Embedded Signup sem callback",
                                       metadata={"phone_number_id": PHONE_NUMBER_ID})
    print("resubscribe: ok")


asyncio.run(main())
