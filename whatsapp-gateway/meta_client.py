"""Meta/WhatsApp Cloud API Client."""
from __future__ import annotations

import logging
from typing import Any, Dict, Optional

import httpx

from config import settings
from schemas import (
    OutgoingDocumentMessage,
    OutgoingImageMessage,
    OutgoingInteractiveButtonsMessage,
    OutgoingInteractiveListMessage,
    OutgoingTemplateMessage,
    OutgoingTextMessage,
    SendMessageResponse,
)

logger = logging.getLogger(__name__)


class MetaAPIClient:
    """Client for WhatsApp Cloud API (Meta)."""

    def __init__(
        self,
        access_token: Optional[str] = None,
        phone_number_id: Optional[str] = None,
        api_version: Optional[str] = None,
    ):
        self.access_token = access_token or settings.META_ACCESS_TOKEN
        self.phone_number_id = phone_number_id or settings.META_PHONE_NUMBER_ID
        self.api_version = api_version or settings.META_API_VERSION
        self.base_url = f"{settings.META_API_BASE_URL}/{self.api_version}"

    def _get_headers(self) -> Dict[str, str]:
        return {
            "Authorization": f"Bearer {self.access_token}",
            "Content-Type": "application/json",
        }

    @property
    def messages_url(self) -> str:
        return f"{self.base_url}/{self.phone_number_id}/messages"

    @property
    def media_url(self) -> str:
        return f"{self.base_url}/{self.phone_number_id}/media"

    async def _send_request(self, payload: Dict[str, Any]) -> SendMessageResponse:
        try:
            async with httpx.AsyncClient(timeout=30.0, headers=self._get_headers()) as client:
                response = await client.post(self.messages_url, json=payload)

            if response.status_code == 200:
                data = response.json()
                message_id = data.get("messages", [{}])[0].get("id")
                logger.info("Message sent successfully: %s", message_id)
                return SendMessageResponse(success=True, message_id=message_id)

            error_data = response.json()
            error_message = error_data.get("error", {}).get("message", "Unknown error")
            logger.error("Failed to send message: %s", error_message)
            return SendMessageResponse(success=False, error=error_message)
        except httpx.RequestError as exc:
            logger.error("Request error: %s", exc)
            return SendMessageResponse(success=False, error=str(exc))
        except Exception as exc:
            logger.error("Unexpected error: %s", exc)
            return SendMessageResponse(success=False, error=str(exc))

    async def send_text_message(self, message: OutgoingTextMessage) -> SendMessageResponse:
        payload = {
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": message.to,
            "type": "text",
            "text": {
                "preview_url": message.preview_url,
                "body": message.text,
            },
        }
        return await self._send_request(payload)

    async def send_image_message(self, message: OutgoingImageMessage) -> SendMessageResponse:
        image_data = {}
        if message.image_url:
            image_data["link"] = message.image_url
        elif message.image_id:
            image_data["id"] = message.image_id
        if message.caption:
            image_data["caption"] = message.caption
        return await self._send_request(
            {
                "messaging_product": "whatsapp",
                "recipient_type": "individual",
                "to": message.to,
                "type": "image",
                "image": image_data,
            }
        )

    async def send_document_message(self, message: OutgoingDocumentMessage) -> SendMessageResponse:
        document_data = {}
        if message.document_url:
            document_data["link"] = message.document_url
        elif message.document_id:
            document_data["id"] = message.document_id
        if message.filename:
            document_data["filename"] = message.filename
        if message.caption:
            document_data["caption"] = message.caption
        return await self._send_request(
            {
                "messaging_product": "whatsapp",
                "recipient_type": "individual",
                "to": message.to,
                "type": "document",
                "document": document_data,
            }
        )

    async def send_interactive_buttons(self, message: OutgoingInteractiveButtonsMessage) -> SendMessageResponse:
        buttons = [
            {"type": "reply", "reply": {"id": btn.id, "title": btn.title[:20]}}
            for btn in message.buttons[:3]
        ]
        interactive_data = {
            "type": "button",
            "body": {"text": message.body_text},
            "action": {"buttons": buttons},
        }
        if message.header_text:
            interactive_data["header"] = {"type": "text", "text": message.header_text}
        if message.footer_text:
            interactive_data["footer"] = {"text": message.footer_text}
        return await self._send_request(
            {
                "messaging_product": "whatsapp",
                "recipient_type": "individual",
                "to": message.to,
                "type": "interactive",
                "interactive": interactive_data,
            }
        )

    async def send_interactive_list(self, message: OutgoingInteractiveListMessage) -> SendMessageResponse:
        sections = [
            {
                "title": section.title,
                "rows": [
                    {
                        "id": row.id,
                        "title": row.title[:24],
                        "description": row.description[:72] if row.description else None,
                    }
                    for row in section.rows[:10]
                ],
            }
            for section in message.sections[:10]
        ]
        interactive_data = {
            "type": "list",
            "body": {"text": message.body_text},
            "action": {"button": message.button_text[:20], "sections": sections},
        }
        if message.header_text:
            interactive_data["header"] = {"type": "text", "text": message.header_text}
        if message.footer_text:
            interactive_data["footer"] = {"text": message.footer_text}
        return await self._send_request(
            {
                "messaging_product": "whatsapp",
                "recipient_type": "individual",
                "to": message.to,
                "type": "interactive",
                "interactive": interactive_data,
            }
        )

    async def send_template_message(self, message: OutgoingTemplateMessage) -> SendMessageResponse:
        template_data = {
            "name": message.template_name,
            "language": {"code": message.language_code},
        }
        if message.components:
            template_data["components"] = message.components
        return await self._send_request(
            {
                "messaging_product": "whatsapp",
                "recipient_type": "individual",
                "to": message.to,
                "type": "template",
                "template": template_data,
            }
        )

    async def mark_as_read(self, message_id: str) -> bool:
        payload = {
            "messaging_product": "whatsapp",
            "status": "read",
            "message_id": message_id,
        }
        try:
            async with httpx.AsyncClient(timeout=30.0, headers=self._get_headers()) as client:
                response = await client.post(self.messages_url, json=payload)
            return response.status_code == 200
        except Exception as exc:
            logger.error("Failed to mark message as read: %s", exc)
            return False

    async def get_media_url(self, media_id: str) -> Optional[str]:
        try:
            async with httpx.AsyncClient(timeout=30.0, headers=self._get_headers()) as client:
                response = await client.get(f"{self.base_url}/{media_id}")
            if response.status_code == 200:
                return response.json().get("url")
            return None
        except Exception as exc:
            logger.error("Failed to get media URL: %s", exc)
            return None

    async def download_media(self, media_url: str) -> Optional[bytes]:
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.get(
                    media_url,
                    headers={"Authorization": f"Bearer {self.access_token}"},
                )
            if response.status_code == 200:
                return response.content
            return None
        except Exception as exc:
            logger.error("Failed to download media: %s", exc)
            return None


def build_meta_client(
    *,
    access_token: Optional[str] = None,
    phone_number_id: Optional[str] = None,
) -> MetaAPIClient:
    return MetaAPIClient(access_token=access_token, phone_number_id=phone_number_id)

