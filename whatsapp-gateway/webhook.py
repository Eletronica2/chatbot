"""
WhatsApp Webhook handlers
"""
import logging
import httpx
from datetime import datetime
from fastapi import APIRouter, Request, HTTPException, Query, BackgroundTasks
from pydantic import BaseModel
from typing import Optional

from config import settings
from schemas import (
    WebhookPayload,
    NormalizedMessage,
    MessageType,
    MessageDirection,
    HealthResponse,
    OutgoingTextMessage,
)
from meta_client import meta_client

logger = logging.getLogger(__name__)

router = APIRouter()


def extract_message_content(message) -> tuple[str, MessageType, Optional[str], Optional[str], Optional[dict]]:
    """
    Extract content from different message types
    Returns: (content, message_type, media_id, media_mime_type, raw_content)
    """
    msg_type = message.type.lower()
    
    if msg_type == "text" and message.text:
        return (
            message.text.body,
            MessageType.TEXT,
            None,
            None,
            {"body": message.text.body}
        )
    
    elif msg_type == "image" and message.image:
        caption = message.image.caption or ""
        return (
            caption or "[Imagem recebida]",
            MessageType.IMAGE,
            message.image.id,
            message.image.mime_type,
            {"id": message.image.id, "caption": caption}
        )
    
    elif msg_type == "audio" and message.audio:
        return (
            "[Áudio recebido]",
            MessageType.AUDIO,
            message.audio.id,
            message.audio.mime_type,
            {"id": message.audio.id}
        )
    
    elif msg_type == "video" and message.video:
        caption = message.video.caption or ""
        return (
            caption or "[Vídeo recebido]",
            MessageType.VIDEO,
            message.video.id,
            message.video.mime_type,
            {"id": message.video.id, "caption": caption}
        )
    
    elif msg_type == "document" and message.document:
        filename = message.document.filename or "documento"
        return (
            f"[Documento: {filename}]",
            MessageType.DOCUMENT,
            message.document.id,
            message.document.mime_type,
            {"id": message.document.id, "filename": filename}
        )
    
    elif msg_type == "location" and message.location:
        location_text = f"Lat: {message.location.latitude}, Lng: {message.location.longitude}"
        if message.location.name:
            location_text = f"{message.location.name} - {location_text}"
        return (
            location_text,
            MessageType.LOCATION,
            None,
            None,
            {
                "latitude": message.location.latitude,
                "longitude": message.location.longitude,
                "name": message.location.name,
                "address": message.location.address
            }
        )
    
    elif msg_type == "contacts" and message.contacts:
        contacts_text = ", ".join([c.name.formatted_name for c in message.contacts])
        return (
            f"[Contatos: {contacts_text}]",
            MessageType.CONTACTS,
            None,
            None,
            {"contacts": [c.dict() for c in message.contacts]}
        )
    
    elif msg_type == "interactive" and message.interactive:
        if message.interactive.button_reply:
            reply = message.interactive.button_reply
            return (
                reply.title or reply.id,
                MessageType.INTERACTIVE,
                None,
                None,
                {"type": "button_reply", "id": reply.id, "title": reply.title}
            )
        elif message.interactive.list_reply:
            reply = message.interactive.list_reply
            return (
                reply.title or reply.id,
                MessageType.INTERACTIVE,
                None,
                None,
                {"type": "list_reply", "id": reply.id, "title": reply.title}
            )
    
    elif msg_type == "button" and message.button:
        return (
            message.button.text,
            MessageType.BUTTON,
            None,
            None,
            {"text": message.button.text, "payload": message.button.payload}
        )
    
    # Unknown type
    return (
        f"[Mensagem tipo: {msg_type}]",
        MessageType.UNKNOWN,
        None,
        None,
        {"type": msg_type}
    )


def normalize_message(
    message,
    metadata,
    contacts,
    tenant_id: str
) -> NormalizedMessage:
    """Normalize incoming WhatsApp message"""
    
    content, msg_type, media_id, media_mime_type, raw_content = extract_message_content(message)
    
    # Get contact name
    contact_name = None
    if contacts:
        for contact in contacts:
            if contact.wa_id == message.from_:
                contact_name = contact.profile.get("name") if contact.profile else None
                break
    
    # Parse timestamp
    try:
        timestamp = datetime.fromtimestamp(int(message.timestamp))
    except (ValueError, TypeError):
        timestamp = datetime.utcnow()
    
    return NormalizedMessage(
        message_id=message.id,
        tenant_id=tenant_id,
        phone_number=message.from_,
        phone_number_id=metadata.phone_number_id,
        display_phone_number=metadata.display_phone_number,
        contact_name=contact_name,
        message_type=msg_type,
        direction=MessageDirection.INCOMING,
        content=content,
        raw_content=raw_content,
        media_id=media_id,
        media_mime_type=media_mime_type,
        timestamp=timestamp,
        metadata={
            "original_type": message.type
        }
    )


async def forward_to_backend(message: NormalizedMessage):
    """Forward normalized message to backend API"""
    try:
        async with httpx.AsyncClient(timeout=settings.BACKEND_API_TIMEOUT) as client:
            response = await client.post(
                f"{settings.BACKEND_API_URL}/api/v1/messages/incoming",
                json=message.model_dump(mode="json")
            )
            
            if response.status_code == 200:
                logger.info(f"Message forwarded to backend: {message.message_id}")

                action = response.json()
                reply_text = action.get("reply_text") if isinstance(action, dict) else None
                metadata = action.get("metadata") if isinstance(action, dict) else None
                reply_to = (
                    action.get("phone_number")
                    if isinstance(action, dict)
                    else None
                ) or message.phone_number

                if reply_text:
                    if isinstance(metadata, dict):
                        options = metadata.get("options")
                        if isinstance(options, list) and options:
                            option_lines = []
                            for option in options:
                                if not isinstance(option, dict):
                                    continue
                                label = option.get("label") or option.get("value")
                                if label:
                                    option_lines.append(f"- {label}")
                            if option_lines:
                                reply_text = f"{reply_text}\n\nOpcoes:\n" + "\n".join(option_lines)

                    send_result = await meta_client.send_text_message(
                        OutgoingTextMessage(to=reply_to, text=str(reply_text))
                    )
                    if send_result.success:
                        logger.info(
                            "Reply sent to WhatsApp for message %s",
                            message.message_id,
                        )
                    else:
                        logger.error(
                            "Failed to send WhatsApp reply for %s: %s",
                            message.message_id,
                            send_result.error,
                        )
            else:
                logger.error(
                    f"Backend returned error: {response.status_code} - {response.text}"
                )
                
    except httpx.RequestError as e:
        logger.error(f"Failed to forward message to backend: {str(e)}")
    except Exception as e:
        logger.error(f"Unexpected error forwarding to backend: {str(e)}")


async def process_webhook_message(
    message,
    metadata,
    contacts,
    tenant_id: str
):
    """Process a single message from webhook"""
    try:
        # Mark as read
        await meta_client.mark_as_read(message.id)
        
        # Normalize message
        normalized = normalize_message(message, metadata, contacts, tenant_id)
        
        logger.info(
            f"Processing message: {normalized.message_id} "
            f"from {normalized.phone_number} "
            f"type: {normalized.message_type}"
        )
        
        # Forward to backend
        await forward_to_backend(normalized)
        
    except Exception as e:
        logger.error(f"Error processing message: {str(e)}")


@router.get("/webhook")
async def verify_webhook(
    hub_mode: str = Query(None, alias="hub.mode"),
    hub_verify_token: str = Query(None, alias="hub.verify_token"),
    hub_challenge: str = Query(None, alias="hub.challenge")
):
    """
    Webhook verification endpoint for Meta
    Called when setting up webhook in Meta Developer Portal
    """
    logger.info(f"Webhook verification: mode={hub_mode}")
    
    if hub_mode == "subscribe" and hub_verify_token == settings.META_VERIFY_TOKEN:
        logger.info("Webhook verified successfully")
        return int(hub_challenge)
    
    logger.warning("Webhook verification failed")
    raise HTTPException(status_code=403, detail="Verification failed")


@router.post("/webhook")
async def receive_webhook(
    request: Request,
    background_tasks: BackgroundTasks,
    tenant_id: str = Query(default=None)
):
    """
    Receive incoming webhook from WhatsApp
    """
    try:
        body = await request.json()
        logger.debug(f"Received webhook: {body}")
        
        # Parse payload
        payload = WebhookPayload(**body)
        
        # Validate it's a WhatsApp message
        if payload.object != "whatsapp_business_account":
            logger.warning(f"Unknown webhook object: {payload.object}")
            return {"status": "ignored"}
        
        # Use tenant from query or default
        current_tenant = tenant_id or settings.DEFAULT_TENANT_ID
        
        # Process each entry
        for entry in payload.entry:
            for change in entry.changes:
                if change.field != "messages":
                    continue
                
                value = change.value
                
                # Skip if no messages (might be status update)
                if not value.messages:
                    if value.statuses:
                        logger.debug(f"Status update received: {value.statuses}")
                    continue
                
                # Process each message in background
                for message in value.messages:
                    background_tasks.add_task(
                        process_webhook_message,
                        message,
                        value.metadata,
                        value.contacts,
                        current_tenant
                    )
        
        return {"status": "ok"}
        
    except Exception as e:
        logger.error(f"Error processing webhook: {str(e)}")
        # Return 200 to prevent Meta from retrying
        return {"status": "error", "message": str(e)}


class SendMessageRequest(BaseModel):
    to: str
    text: str


@router.post("/send-message")
async def send_message(body: SendMessageRequest):
    """Send a WhatsApp text message. Used by admin panel agents to reply manually."""
    if not body.to or not body.text:
        raise HTTPException(status_code=422, detail="to and text are required")

    result = await meta_client.send_text_message(
        OutgoingTextMessage(to=body.to, text=body.text)
    )
    if not result.success:
        raise HTTPException(status_code=502, detail=f"Meta API error: {result.error}")
    return {"ok": True}


@router.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    return HealthResponse(
        status="healthy",
        service=settings.APP_NAME,
        version=settings.APP_VERSION,
        timestamp=datetime.utcnow()
    )
