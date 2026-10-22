"""Probe whatsapp_business_messaging for the Bella Massa number WITHOUT sending a message.

Marks the latest already-processed inbound message as read (the Gateway does the same on every inbound),
once with the account token and once with the partner System User token. Prints status/error codes only.
Run inside backend-api:  python - < scripts/ia03_messaging_permission_probe.py
"""
import asyncio

import httpx

from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.repositories.whatsapp_account_repository import WhatsAppAccountRepository
from app.security.crypto import TokenCipher
from app.services.meta_graph_service import MetaGraphService
from app.services.whatsapp_account_service import WhatsAppAccountService

PHONE_NUMBER_ID = "1155710810954749"


async def main() -> None:
    db = MySQLDatabase(settings.DATABASE_URL)
    row = db.fetch_one(
        "SELECT external_message_id FROM messages WHERE tenant_id=5 AND direction='incoming' "
        "AND phone_number_id=%s ORDER BY id DESC LIMIT 1", (PHONE_NUMBER_ID,))
    wamid = row["external_message_id"]
    account = await WhatsAppAccountService(WhatsAppAccountRepository(db), TokenCipher(settings.APP_SECRET_KEY),
                                           MetaGraphService()).resolve_for_phone_number_id(PHONE_NUMBER_ID)
    version = getattr(settings, "META_API_VERSION", None) or "v22.0"
    body = {"messaging_product": "whatsapp", "status": "read", "message_id": wamid}
    async with httpx.AsyncClient(base_url=f"https://graph.facebook.com/{version}", timeout=20) as client:
        for label, token in (("token da conta Bella (Embedded Signup)", account.access_token),
                             ("token System User do parceiro", (settings.META_SYSTEM_USER_TOKEN or "").strip())):
            response = await client.post(f"/{PHONE_NUMBER_ID}/messages", json=body,
                                         headers={"Authorization": f"Bearer {token}"})
            error = (response.json() or {}).get("error") or {}
            print(f"{label}: HTTP {response.status_code} code={error.get('code')} "
                  f"subcode={error.get('error_subcode')} msg={str(error.get('message'))[:140]}")


asyncio.run(main())
