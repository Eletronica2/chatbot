"""Read-only Meta token diagnosis for the Bella Massa WhatsApp account (debug_token; nothing is sent or changed).

Run inside backend-api:  python - < scripts/ia03_debug_wa_token.py
Prints validity, type, expiry and scopes only; never prints a token.
"""
import asyncio
import datetime

import httpx

from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.repositories.whatsapp_account_repository import WhatsAppAccountRepository
from app.security.crypto import TokenCipher
from app.services.meta_graph_service import MetaGraphService
from app.services.whatsapp_account_service import WhatsAppAccountService

PHONE_NUMBER_ID = "1155710810954749"


async def main() -> None:
    service = WhatsAppAccountService(WhatsAppAccountRepository(MySQLDatabase(settings.DATABASE_URL)),
                                     TokenCipher(settings.APP_SECRET_KEY), MetaGraphService())
    account = await service.resolve_for_phone_number_id(PHONE_NUMBER_ID)
    app_token = f"{settings.META_APP_ID}|{settings.META_APP_SECRET}"
    version = getattr(settings, "META_API_VERSION", None) or "v22.0"
    tokens = (("conta Bella (Embedded Signup)", account.access_token if account else None),
              ("META_SYSTEM_USER_TOKEN", (settings.META_SYSTEM_USER_TOKEN or "").strip() or None))
    async with httpx.AsyncClient(base_url=f"https://graph.facebook.com/{version}", timeout=20) as client:
        for label, token in tokens:
            if not token:
                print(f"{label}: ausente")
                continue
            data = (await client.get("/debug_token", params={"input_token": token, "access_token": app_token})).json()
            data = data.get("data", {})
            expires = data.get("expires_at")
            expires = "nunca" if not expires else datetime.datetime.utcfromtimestamp(expires).isoformat()
            print(f"\n{label}: valid={data.get('is_valid')} type={data.get('type')} "
                  f"app_ok={str(data.get('app_id')) == str(settings.META_APP_ID)} expira={expires} "
                  f"profile_or_user={'sim' if data.get('user_id') or data.get('profile_id') else 'nao'}")
            print("  scopes:", data.get("scopes"))
            for granular in data.get("granular_scopes", []):
                print("  granular:", granular.get("scope"), "->", granular.get("target_ids", "todos os ativos"))
            if data.get("error"):
                print("  erro:", data["error"].get("message"))


asyncio.run(main())
