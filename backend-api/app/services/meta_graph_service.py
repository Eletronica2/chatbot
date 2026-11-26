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
            err = payload.get("error") if isinstance(payload.get("error"), dict) else {}
            message = err.get("message") or response.text
            user_msg = err.get("error_user_msg")
            if user_msg:
                message = f"{message} — {user_msg}"
            code = err.get("code")
            if code is not None:
                message = f"(#{code}) {message}"
            sub = err.get("error_subcode")
            trace = err.get("fbtrace_id")
            extras: list[str] = []
            if sub is not None:
                extras.append(f"error_subcode={sub}")
            if trace:
                extras.append(f"fbtrace_id={trace}")
            if extras:
                message = f"{message} ({'; '.join(extras)})"
            raise ValueError(message)
        return response.json()

    async def debug_token(self, input_token: str) -> dict[str, Any]:
        if not self.app_id or not self.app_secret:
            return {"data": {"is_valid": True, "expires_at": 0}}
        app_access_token = f"{self.app_id}|{self.app_secret}"
        async with httpx.AsyncClient(timeout=settings.META_API_TIMEOUT) as client:
            response = await client.get(
                self._url("/debug_token"),
                params={
                    "input_token": input_token,
                    "access_token": app_access_token,
                },
            )
        if response.status_code >= 400:
            logger.warning("Meta debug_token error: %s", response.text)
            return {"data": {"is_valid": False}}
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

    async def list_app_webhook_subscriptions(self, access_token: str) -> list[str]:
        """App-level WhatsApp webhook fields (read-only; does not change WABA subscriptions)."""
        app_id = (self.app_id or "").strip()
        app_secret = (self.app_secret or "").strip()
        if not app_id:
            return []
        token = access_token
        if app_id and app_secret:
            token = f"{app_id}|{app_secret}"
        payload = await self._request(
            "GET",
            f"/{app_id}/subscriptions",
            access_token=token,
        )
        rows = payload.get("data") if isinstance(payload, dict) else None
        fields: list[str] = []
        for row in rows or []:
            if not isinstance(row, dict):
                continue
            for item in row.get("fields") or []:
                if isinstance(item, dict):
                    name = str(item.get("name") or "").strip()
                else:
                    name = str(item).strip()
                if name:
                    fields.append(name)
        return sorted(set(fields))

    async def assert_phone_on_messaging_account(
        self,
        *,
        messaging_account_id: str,
        phone_number_id: str,
        access_token: str,
    ) -> None:
        """Ensure the phone belongs to the messaging account before linking to a tenant."""
        payload = await self._request(
            "GET",
            f"/{messaging_account_id}/phone_numbers",
            access_token=access_token,
            params={"fields": "id", "limit": 100},
        )
        rows = payload.get("data") if isinstance(payload, dict) else None
        ids = {str(item.get("id") or "").strip() for item in rows or [] if isinstance(item, dict)}
        if phone_number_id.strip() not in ids:
            raise ValueError("O número informado não pertence à conta de mensagens autorizada")

    async def get_phone_number_status(self, phone_number_id: str, access_token: str) -> dict[str, Any]:
        return await self._request(
            "GET",
            f"/{phone_number_id}",
            access_token=access_token,
            params={"fields": "display_phone_number,is_on_biz_app,platform_type,verified_name"},
        )

    async def try_pricing_analytics(
        self,
        waba_id: str,
        access_token: str,
        *,
        start: int | None = None,
        end: int | None = None,
    ) -> dict[str, Any] | None:
        """Best-effort pricing_analytics; returns None when unavailable."""
        params: dict[str, Any] = {}
        if start is not None:
            params["start"] = start
        if end is not None:
            params["end"] = end
        try:
            return await self._request(
                "GET",
                f"/{waba_id}/pricing_analytics",
                access_token=access_token,
                params=params or None,
            )
        except Exception:
            return None

    async def list_message_templates(self, waba_id: str, access_token: str) -> list[dict[str, Any]]:
        payload = await self._request(
            "GET",
            f"/{waba_id}/message_templates",
            access_token=access_token,
            params={
                "limit": 100,
                "fields": "name,status,language,category,id,components,rejected_reason",
            },
        )
        data = payload.get("data")
        return data if isinstance(data, list) else []

    @staticmethod
    def build_template_components(
        *,
        body_text: str,
        footer_text: str | None = None,
        header: dict[str, Any] | None = None,
        buttons: list[dict[str, Any]] | None = None,
        body_examples: list[str] | None = None,
    ) -> list[dict[str, Any]]:
        components: list[dict[str, Any]] = []
        if header:
            hf = str(header.get("format") or "TEXT").upper()
            block: dict[str, Any] = {"type": "HEADER", "format": hf}
            if hf == "TEXT":
                block["text"] = str(header.get("text") or "")
            elif header.get("media_url"):
                block["example"] = {"header_handle": [str(header["media_url"])]}
            components.append(block)
        body: dict[str, Any] = {"type": "BODY", "text": body_text}
        if body_examples:
            body["example"] = {"body_text": [body_examples]}
        components.append(body)
        if footer_text:
            components.append({"type": "FOOTER", "text": footer_text})
        if buttons:
            mapped: list[dict[str, Any]] = []
            for btn in buttons:
                btype = str(btn.get("type") or "QUICK_REPLY").upper()
                item: dict[str, Any] = {"type": btype, "text": str(btn.get("text") or "")}
                if btype == "PHONE_NUMBER" and btn.get("phone_number"):
                    item["phone_number"] = str(btn["phone_number"])
                if btype == "URL" and btn.get("url"):
                    item["url"] = str(btn["url"])
                    if btn.get("example"):
                        item["example"] = btn["example"]
                if btype == "COPY_CODE" and btn.get("example"):
                    item["example"] = btn["example"]
                mapped.append(item)
            if mapped:
                components.append({"type": "BUTTONS", "buttons": mapped})
        return components

    async def create_message_template(
        self,
        *,
        waba_id: str,
        access_token: str,
        name: str,
        language: str,
        category: str,
        body_text: str,
        components: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        payload_components = components or [{"type": "BODY", "text": body_text}]
        return await self._request(
            "POST",
            f"/{waba_id}/message_templates",
            access_token=access_token,
            json_body={
                "name": name,
                "language": language,
                "category": category,
                "components": payload_components,
            },
        )
