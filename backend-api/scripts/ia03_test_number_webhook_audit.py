"""Read-only audit of webhook delivery config for the Atende Ai Meta test number (no sends, no changes).

Checks app-level subscriptions, Messaging account subscribed_apps (incl. override_callback_uri), the phone number's
webhook_configuration and the stored routing. Run inside backend-api:
    python - < scripts/ia03_test_number_webhook_audit.py
"""
import asyncio
import json

import httpx

from app.config.settings import settings
from app.db.mysql import MySQLDatabase

PNID, WABA = "1201264079728608", "27281965408107469"


async def main() -> None:
    token = (settings.META_SYSTEM_USER_TOKEN or "").strip()
    app_token = f"{settings.META_APP_ID}|{settings.META_APP_SECRET}"
    version = getattr(settings, "META_API_VERSION", None) or "v22.0"
    async with httpx.AsyncClient(base_url=f"https://graph.facebook.com/{version}", timeout=20) as client:
        async def get(path, tok, **params):
            data = (await client.get(path, params={"access_token": tok, **params})).json()
            data.pop("paging", None)
            return data
        subs = await get(f"/{settings.META_APP_ID}/subscriptions", app_token)
        for sub in subs.get("data", []):
            print("app subscription:", sub.get("object"), "active=", sub.get("active"), "callback=",
                  sub.get("callback_url"), "fields=", sorted(f.get("name") for f in sub.get("fields", [])))
        print("waba subscribed_apps:", json.dumps(await get(f"/{WABA}/subscribed_apps", token), ensure_ascii=False))
        print("phone:", json.dumps(await get(f"/{PNID}", token, fields="id,display_phone_number,verified_name,status,"
                                              "platform_type,account_mode,webhook_configuration,throughput,"
                                              "health_status"), ensure_ascii=False))
        print("waba:", json.dumps(await get(f"/{WABA}", token, fields="id,name,status,account_review_status,"
                                             "ownership_type,on_behalf_of_business_info"), ensure_ascii=False))
    db = MySQLDatabase(settings.DATABASE_URL)
    print("routing rows:", db.fetch_all("SELECT id, tenant_id, account_key, status, is_default FROM whatsapp_accounts "
                                        "WHERE phone_number_id=%s", (PNID,)))


asyncio.run(main())
