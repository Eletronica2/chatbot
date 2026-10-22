"""Read-only Meta diagnosis of why the Bella Massa number cannot send (health_status, ownership, review state).

Run inside backend-api:  python - < scripts/ia03_wa_health.py
GET requests only; nothing is sent or changed; tokens are never printed.
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

PHONE_NUMBER_ID = "1155710810954749"
WABA_ID = "1299741078262298"


async def get(client, path, token, fields=None):
    params = {"access_token": token}
    if fields:
        params["fields"] = fields
    response = await client.get(path, params=params)
    data = response.json()
    if "error" in data:
        err = data["error"]
        return {"error": {k: err.get(k) for k in ("code", "error_subcode", "type", "message")}}
    return data


async def main() -> None:
    service = WhatsAppAccountService(WhatsAppAccountRepository(MySQLDatabase(settings.DATABASE_URL)),
                                     TokenCipher(settings.APP_SECRET_KEY), MetaGraphService())
    account = await service.resolve_for_phone_number_id(PHONE_NUMBER_ID)
    version = getattr(settings, "META_API_VERSION", None) or "v22.0"
    app_token = f"{settings.META_APP_ID}|{settings.META_APP_SECRET}"
    async with httpx.AsyncClient(base_url=f"https://graph.facebook.com/{version}", timeout=20) as client:
        for label, token in (("token da conta Bella", account.access_token),
                             ("META_SYSTEM_USER_TOKEN", (settings.META_SYSTEM_USER_TOKEN or "").strip())):
            if not token:
                continue
            print(f"\n######## {label}")
            for title, path, fields in (
                ("numero", f"/{PHONE_NUMBER_ID}", "id,display_phone_number,verified_name,status,name_status,"
                 "new_name_status,code_verification_status,quality_rating,platform_type,account_mode,"
                 "messaging_limit_tier,throughput,is_pin_enabled,is_official_business_account,health_status"),
                ("waba", f"/{WABA_ID}", "id,name,account_review_status,business_verification_status,ownership_type,"
                 "owner_business_info,currency,timezone_id,health_status"),
                ("waba extra", f"/{WABA_ID}", "status,is_shared_with_partners,on_behalf_of_business_info,"
                 "whatsapp_business_manager_messaging_limit,country,primary_business_location"),
                ("numero extra", f"/{PHONE_NUMBER_ID}", "is_on_biz_app,last_onboarded_time,webhook_configuration,"
                 "certificate,status,search_visibility"),
                ("numeros da waba", f"/{WABA_ID}/phone_numbers", "id,display_phone_number,status"),
                ("apps assinados", f"/{WABA_ID}/subscribed_apps", None),
            ):
                print(f"== {title}:", json.dumps(await get(client, path, token, fields), ensure_ascii=False))
        print("\n######## app")
        print(json.dumps(await get(client, f"/{settings.META_APP_ID}", app_token, "id,name,link"), ensure_ascii=False))


asyncio.run(main())
