"""Read-only: which Business Portfolio owns the app and each token identity (no token is printed).

Run inside backend-api:  python - < scripts/ia03_identity_owners.py
"""
import asyncio
import json

import httpx

from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.repositories.whatsapp_account_repository import WhatsAppAccountRepository
from app.security.crypto import TokenCipher
from app.services.meta_graph_service import MetaGraphService
from app.services.whatsapp_account_service import WhatsAppAccountService


async def get(client, path, token, fields=None):
    params = {"access_token": token}
    if fields:
        params["fields"] = fields
    data = (await client.get(path, params=params)).json()
    if "error" in data:
        return {"error": {k: data["error"].get(k) for k in ("code", "message")}}
    return data


async def main() -> None:
    version = getattr(settings, "META_API_VERSION", None) or "v22.0"
    app_token = f"{settings.META_APP_ID}|{settings.META_APP_SECRET}"
    db = MySQLDatabase(settings.DATABASE_URL)
    account = await WhatsAppAccountService(WhatsAppAccountRepository(db), TokenCipher(settings.APP_SECRET_KEY),
                                           MetaGraphService()).resolve_for_phone_number_id("1155710810954749")
    partner = (settings.META_SYSTEM_USER_TOKEN or "").strip()
    async with httpx.AsyncClient(base_url=f"https://graph.facebook.com/{version}", timeout=20) as client:
        print("app:", json.dumps(await get(client, f"/{settings.META_APP_ID}", app_token, "id,name,business"), ensure_ascii=False))
        for label, token in (("token atual da conta Bella", account.access_token), ("META_SYSTEM_USER_TOKEN", partner)):
            debug = (await client.get("/debug_token", params={"input_token": token, "access_token": app_token})).json().get("data", {})
            print(f"\n{label}: same_as_partner={token == partner} type={debug.get('type')} user_id={debug.get('user_id')} profile_id={debug.get('profile_id')}")
            print("  me:", json.dumps(await get(client, "/me", token, "id,name"), ensure_ascii=False))
            print("  me/businesses:", json.dumps(await get(client, "/me/businesses", token, "id,name,verification_status"), ensure_ascii=False)[:600])
        for biz in ("2330602324386620", "506485032393364", "1348385330573371"):
            print(f"\nbusiness {biz}:", json.dumps(await get(client, f"/{biz}", partner, "id,name,verification_status"), ensure_ascii=False))


asyncio.run(main())
