"""HTTP client for Meta Graph API (WhatsApp Business Platform)."""
from __future__ import annotations

import logging
from typing import Any

import httpx

from app.config.settings import settings

logger = logging.getLogger(__name__)


class MetaGraphService:
    def __init__(
        self,
        *,
        api_version: str | None = None,
        app_id: str | None = None,
        app_secret: str | None = None,
    ):
        self.api_version = api_version or settings.META_API_VERSION
        self.app_id = app_id or settings.META_APP_ID
        self.app_secret = app_secret or settings.META_APP_SECRET
        self.base_url = settings.META_API_BASE_URL.rstrip("/")

    def _url(self, path: str) -> str:
        normalized = path if path.startswith("/") else f"/{path}"
        return f"{self.base_url}/{self.api_version}{normalized}"

    async def _request(
        self,
        method: str,
        path: str,
        *,
        access_token: str,
        params: dict[str, Any] | None = None,
        json_body: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        query = dict(params or {})
        query["access_token"] = access_token
        async with httpx.AsyncClient(timeout=settings.META_API_TIMEOUT) as client:
            response = await client.request(
                method,
                self._url(path),
                params=query,
                json=json_body,
            )
        if response.status_code >= 400:
            logger.warning("Meta Graph API error %s %s: %s", method, path, response.text)
            try:
                payload = response.json()
            except Exception:
                payload = {"error": {"message": response.text}}
            message = payload.get("error", {}).get("message") or response.text
            raise ValueError(message)
        return response.json()

    async def exchange_code_for_token(self, code: str, redirect_uri: str | None = None) -> str:
        if not self.app_id or not self.app_secret:
            raise ValueError("META_APP_ID e META_APP_SECRET devem estar configurados")
        params: dict[str, Any] = {
            "client_id": self.app_id,
            "client_secret": self.app_secret,
            "code": code,
        }
        if redirect_uri:
            params["redirect_uri"] = redirect_uri
        async with httpx.AsyncClient(timeout=settings.META_API_TIMEOUT) as client:
            response = await client.get(self._url("/oauth/access_token"), params=params)
        if response.status_code >= 400:
            raise ValueError(response.text)
        payload = response.json()
        token = payload.get("access_token")
        if not token:
            raise ValueError("Meta nao retornou access_token")
        return str(token)

    async def subscribe_waba_webhooks(self, waba_id: str, access_token: str) -> None:
        await self._request("POST", f"/{waba_id}/subscribed_apps", access_token=access_token)

    async def get_phone_number_status(self, phone_number_id: str, access_token: str) -> dict[str, Any]:
        return await self._request(
            "GET",
            f"/{phone_number_id}",
            access_token=access_token,
            params={"fields": "display_phone_number,is_on_biz_app,platform_type,verified_name"},
        )

    async def list_message_templates(self, waba_id: str, access_token: str) -> list[dict[str, Any]]:
        payload = await self._request(
            "GET",
            f"/{waba_id}/message_templates",
            access_token=access_token,
            params={"limit": 100, "fields": "name,status,language,category,id,components"},
        )
        data = payload.get("data")
        return data if isinstance(data, list) else []

    async def create_message_template(
        self,
        *,
        waba_id: str,
        access_token: str,
        name: str,
        language: str,
        category: str,
        body_text: str,
    ) -> dict[str, Any]:
        return await self._request(
            "POST",
            f"/{waba_id}/message_templates",
            access_token=access_token,
            json_body={
                "name": name,
                "language": language,
                "category": category,
                "components": [{"type": "BODY", "text": body_text}],
            },
        )
