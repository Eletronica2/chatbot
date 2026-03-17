"""
Meta/WhatsApp Cloud API Client
"""
import httpx
import logging
from typing import Optional, Dict, Any
from config import settings
from schemas import (
    OutgoingTextMessage,
    OutgoingImageMessage,
    OutgoingDocumentMessage,
    OutgoingInteractiveButtonsMessage,
    OutgoingInteractiveListMessage,
    OutgoingTemplateMessage,
    SendMessageResponse
)

logger = logging.getLogger(__name__)


class MetaAPIClient:
    """Client for WhatsApp Cloud API (Meta)"""
    
    def __init__(
        self,
        access_token: Optional[str] = None,
        phone_number_id: Optional[str] = None,
        api_version: Optional[str] = None
    ):
        self.access_token = access_token or settings.META_ACCESS_TOKEN
        self.phone_number_id = phone_number_id or settings.META_PHONE_NUMBER_ID
        self.api_version = api_version or settings.META_API_VERSION
        self.base_url = f"{settings.META_API_BASE_URL}/{self.api_version}"
        
        self._client = httpx.AsyncClient(
            timeout=30.0,
            headers=self._get_headers()
        )
    
    def _get_headers(self) -> Dict[str, str]:
        """Get default headers for API requests"""
        return {
            "Authorization": f"Bearer {self.access_token}",
            "Content-Type": "application/json"
        }
    
    @property
    def messages_url(self) -> str:
        """Get messages endpoint URL"""
        return f"{self.base_url}/{self.phone_number_id}/messages"
    
    @property
    def media_url(self) -> str:
        """Get media endpoint URL"""
        return f"{self.base_url}/{self.phone_number_id}/media"
    
    async def _send_request(self, payload: Dict[str, Any]) -> SendMessageResponse:
        """Send request to WhatsApp API"""
        try:
            response = await self._client.post(
                self.messages_url,
                json=payload
            )
            
            if response.status_code == 200:
                data = response.json()
                message_id = data.get("messages", [{}])[0].get("id")
                logger.info(f"Message sent successfully: {message_id}")
                return SendMessageResponse(success=True, message_id=message_id)
            else:
                error_data = response.json()
                error_message = error_data.get("error", {}).get("message", "Unknown error")
                logger.error(f"Failed to send message: {error_message}")
                return SendMessageResponse(success=False, error=error_message)
                
        except httpx.RequestError as e:
            logger.error(f"Request error: {str(e)}")
            return SendMessageResponse(success=False, error=str(e))
        except Exception as e:
            logger.error(f"Unexpected error: {str(e)}")
            return SendMessageResponse(success=False, error=str(e))
    
    async def send_text_message(self, message: OutgoingTextMessage) -> SendMessageResponse:
        """Send a text message"""
        payload = {
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": message.to,
            "type": "text",
            "text": {
                "preview_url": message.preview_url,
                "body": message.text
            }
        }
        return await self._send_request(payload)
    
    async def send_image_message(self, message: OutgoingImageMessage) -> SendMessageResponse:
        """Send an image message"""
        image_data = {}
        if message.image_url:
            image_data["link"] = message.image_url
        elif message.image_id:
            image_data["id"] = message.image_id
        
        if message.caption:
            image_data["caption"] = message.caption
        
        payload = {
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": message.to,
            "type": "image",
            "image": image_data
        }
        return await self._send_request(payload)
    
    async def send_document_message(self, message: OutgoingDocumentMessage) -> SendMessageResponse:
        """Send a document message"""
        document_data = {}
        if message.document_url:
            document_data["link"] = message.document_url
        elif message.document_id:
            document_data["id"] = message.document_id
        
        if message.filename:
            document_data["filename"] = message.filename
        if message.caption:
            document_data["caption"] = message.caption
        
        payload = {
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": message.to,
            "type": "document",
            "document": document_data
        }
        return await self._send_request(payload)
    
    async def send_interactive_buttons(
        self, 
        message: OutgoingInteractiveButtonsMessage
    ) -> SendMessageResponse:
        """Send an interactive message with buttons"""
        buttons = [
            {
                "type": "reply",
                "reply": {
                    "id": btn.id,
                    "title": btn.title[:20]  # Max 20 chars
                }
            }
            for btn in message.buttons[:3]  # Max 3 buttons
        ]
        
        interactive_data = {
            "type": "button",
            "body": {"text": message.body_text},
            "action": {"buttons": buttons}
        }
        
        if message.header_text:
            interactive_data["header"] = {
                "type": "text",
                "text": message.header_text
            }
        
        if message.footer_text:
            interactive_data["footer"] = {"text": message.footer_text}
        
        payload = {
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": message.to,
            "type": "interactive",
            "interactive": interactive_data
        }
        return await self._send_request(payload)
    
    async def send_interactive_list(
        self, 
        message: OutgoingInteractiveListMessage
    ) -> SendMessageResponse:
        """Send an interactive message with list"""
        sections = [
            {
                "title": section.title,
                "rows": [
                    {
                        "id": row.id,
                        "title": row.title[:24],  # Max 24 chars
                        "description": row.description[:72] if row.description else None
                    }
                    for row in section.rows[:10]  # Max 10 rows per section
                ]
            }
            for section in message.sections[:10]  # Max 10 sections
        ]
        
        interactive_data = {
            "type": "list",
            "body": {"text": message.body_text},
            "action": {
                "button": message.button_text[:20],  # Max 20 chars
                "sections": sections
            }
        }
        
        if message.header_text:
            interactive_data["header"] = {
                "type": "text",
                "text": message.header_text
            }
        
        if message.footer_text:
            interactive_data["footer"] = {"text": message.footer_text}
        
        payload = {
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": message.to,
            "type": "interactive",
            "interactive": interactive_data
        }
        return await self._send_request(payload)
    
    async def send_template_message(
        self, 
        message: OutgoingTemplateMessage
    ) -> SendMessageResponse:
        """Send a template message"""
        template_data = {
            "name": message.template_name,
            "language": {"code": message.language_code}
        }
        
        if message.components:
            template_data["components"] = message.components
        
        payload = {
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": message.to,
            "type": "template",
            "template": template_data
        }
        return await self._send_request(payload)
    
    async def mark_as_read(self, message_id: str) -> bool:
        """Mark a message as read"""
        payload = {
            "messaging_product": "whatsapp",
            "status": "read",
            "message_id": message_id
        }
        
        try:
            response = await self._client.post(
                self.messages_url,
                json=payload
            )
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Failed to mark message as read: {str(e)}")
            return False
    
    async def get_media_url(self, media_id: str) -> Optional[str]:
        """Get download URL for a media file"""
        try:
            url = f"{self.base_url}/{media_id}"
            response = await self._client.get(url)
            
            if response.status_code == 200:
                return response.json().get("url")
            return None
        except Exception as e:
            logger.error(f"Failed to get media URL: {str(e)}")
            return None
    
    async def download_media(self, media_url: str) -> Optional[bytes]:
        """Download media file content"""
        try:
            response = await self._client.get(
                media_url,
                headers={"Authorization": f"Bearer {self.access_token}"}
            )
            
            if response.status_code == 200:
                return response.content
            return None
        except Exception as e:
            logger.error(f"Failed to download media: {str(e)}")
            return None
    
    async def close(self):
        """Close the HTTP client"""
        await self._client.aclose()


# Singleton instance
meta_client = MetaAPIClient()


async def get_meta_client() -> MetaAPIClient:
    """Get Meta API client instance"""
    return meta_client
