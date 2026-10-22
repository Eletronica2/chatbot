"""Read-only look at the Atende Ai portfolio's own Messaging accounts (test number) with the System User token.

Run inside backend-api:  python - < scripts/ia03_atendeai_test_waba.py
GET requests only; nothing is sent, registered or changed; tokens are never printed.
"""
import asyncio
import json

import httpx

from app.config.settings import settings

BUSINESS_ID = "506485032393364"
TEST_WABA = "27281965408107469"


async def get(client, path, token, fields=None):
    params = {"access_token": token}
    if fields:
        params["fields"] = fields
    data = (await client.get(path, params=params)).json()
    if "error" in data:
        err = data["error"]
        return {"error": {k: err.get(k) for k in ("code", "error_subcode", "message")}}
    data.pop("paging", None)
    return data


async def main() -> None:
    token = (settings.META_SYSTEM_USER_TOKEN or "").strip()
    app_token = f"{settings.META_APP_ID}|{settings.META_APP_SECRET}"
    version = getattr(settings, "META_API_VERSION", None) or "v22.0"
    async with httpx.AsyncClient(base_url=f"https://graph.facebook.com/{version}", timeout=20) as client:
        debug = (await client.get("/debug_token", params={"input_token": token, "access_token": app_token})).json()
        info = debug.get("data", {})
        print("system user token:", json.dumps({"valid": info.get("is_valid"), "type": info.get("type"),
                                                "expires_at": info.get("expires_at"),
                                                "granular": info.get("granular_scopes")}, ensure_ascii=False))
        for title, path, fields in (
            ("waba proprias", f"/{BUSINESS_ID}/owned_whatsapp_business_accounts", "id,name,account_review_status,ownership_type"),
            ("test waba", f"/{TEST_WABA}", "id,name,account_review_status,business_verification_status,ownership_type,"
             "status,health_status"),
            ("numeros test waba", f"/{TEST_WABA}/phone_numbers", "id,display_phone_number,verified_name,status,"
             "platform_type,account_mode,is_on_biz_app,messaging_limit_tier,code_verification_status"),
            ("apps assinados test waba", f"/{TEST_WABA}/subscribed_apps", None),
        ):
            print(f"== {title}:", json.dumps(await get(client, path, token, fields), ensure_ascii=False))


asyncio.run(main())
