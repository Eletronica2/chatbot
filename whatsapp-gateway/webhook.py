"""WhatsApp Webhook handlers."""
from __future__ import annotations

import hashlib
import hmac
import json
import logging
from datetime import datetime
from typing import Optional

import httpx
from fastapi import APIRouter, BackgroundTasks, HTTPException, Query, Request
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel

from config import settings
from meta_client import build_meta_client
from phone_utils import normalize_whatsapp_to
from schemas import (
    HealthResponse,
    MessageDirection,
    MessageType,
    NormalizedMessage,
    OutgoingTemplateMessage,
    OutgoingTextMessage,
    WebhookPayload,
)

logger = logging.getLogger(__name__)
router = APIRouter()


def extract_message_content(message) -> tuple[str, MessageType, Optional[str], Optional[str], Optional[dict]]:
    msg_type = message.type.lower()

    if msg_type == "text" and message.text:
        return (message.text.body, MessageType.TEXT, None, None, {"body": message.text.body})
    if msg_type == "image" and message.image:
        caption = message.image.caption or ""
        return (caption or "[Imagem recebida]", MessageType.IMAGE, message.image.id, message.image.mime_type, {"id": message.image.id, "caption": caption})
    if msg_type == "audio" and message.audio:
        return ("[Audio recebido]", MessageType.AUDIO, message.audio.id, message.audio.mime_type, {"id": message.audio.id})
    if msg_type == "video" and message.video:
        caption = message.video.caption or ""
        return (caption or "[Video recebido]", MessageType.VIDEO, message.video.id, message.video.mime_type, {"id": message.video.id, "caption": caption})
    if msg_type == "document" and message.document:
        filename = message.document.filename or "documento"
        return (f"[Documento: {filename}]", MessageType.DOCUMENT, message.document.id, message.document.mime_type, {"id": message.document.id, "filename": filename})
    if msg_type == "location" and message.location:
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
                "address": message.location.address,
            },
        )
    if msg_type == "contacts" and message.contacts:
        contacts_text = ", ".join([c.name.formatted_name for c in message.contacts])
        return (f"[Contatos: {contacts_text}]", MessageType.CONTACTS, None, None, {"contacts": [c.dict() for c in message.contacts]})
    if msg_type == "interactive" and message.interactive:
        if message.interactive.button_reply:
            reply = message.interactive.button_reply
            return (reply.title or reply.id, MessageType.INTERACTIVE, None, None, {"type": "button_reply", "id": reply.id, "title": reply.title})
        if message.interactive.list_reply:
            reply = message.interactive.list_reply
            return (reply.title or reply.id, MessageType.INTERACTIVE, None, None, {"type": "list_reply", "id": reply.id, "title": reply.title})
    if msg_type == "button" and message.button:
        return (message.button.text, MessageType.BUTTON, None, None, {"text": message.button.text, "payload": message.button.payload})
    return (f"[Mensagem tipo: {msg_type}]", MessageType.UNKNOWN, None, None, {"type": msg_type})


def normalize_message(message, metadata, contacts, tenant_id: str) -> NormalizedMessage:
    content, msg_type, media_id, media_mime_type, raw_content = extract_message_content(message)
    contact_name = None
    if contacts:
        for contact in contacts:
            if contact.wa_id == message.from_:
                contact_name = contact.profile.get("name") if contact.profile else None
                break
    try:
        timestamp = datetime.fromtimestamp(int(message.timestamp))
    except (ValueError, TypeError):
        timestamp = datetime.utcnow()
    return NormalizedMessage(
        message_id=message.id,
        tenant_id=tenant_id,
        phone_number=normalize_whatsapp_to(message.from_),
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
        metadata={"original_type": message.type},
    )


async def _resolve_account_context(*, tenant_id: str | None = None, phone_number_id: str | None = None) -> dict | None:
    try:
        async with httpx.AsyncClient(timeout=settings.BACKEND_API_TIMEOUT) as client:
            response = await client.post(
                f"{settings.BACKEND_API_URL}/api/v1/internal/whatsapp/resolve",
                headers={"x-internal-api-key": settings.BACKEND_INTERNAL_API_KEY},
                json={"tenant_id": tenant_id, "phone_number_id": phone_number_id},
            )
        if response.status_code == 200:
            data = response.json()
            if isinstance(data, dict) and data.get("found"):
                return data
    except Exception as exc:
        logger.warning("Could not resolve WhatsApp account via backend: %s", exc)
    return None


async def _validate_verify_token(token: str) -> bool:
    try:
        async with httpx.AsyncClient(timeout=settings.BACKEND_API_TIMEOUT) as client:
            response = await client.post(
                f"{settings.BACKEND_API_URL}/api/v1/internal/whatsapp/verify-token",
                headers={"x-internal-api-key": settings.BACKEND_INTERNAL_API_KEY},
                json={"verify_token": token},
            )
        if response.status_code == 200:
            payload = response.json()
            return bool(payload.get("valid"))
    except Exception as exc:
        logger.warning("Could not validate verify token via backend: %s", exc)
    return False


def _fallback_account_context(tenant_id: str | None = None, phone_number_id: str | None = None) -> dict | None:
    if not settings.META_ACCESS_TOKEN or not settings.META_PHONE_NUMBER_ID:
        return None
    return {
        "found": True,
        "tenant_id": tenant_id or settings.DEFAULT_TENANT_ID,
        "account_key": "default-env",
        "display_name": "Conta padrao",
        "phone_number_id": phone_number_id or settings.META_PHONE_NUMBER_ID,
        "display_phone_number": settings.META_PHONE_NUMBER_ID,
        "verify_token": settings.META_VERIFY_TOKEN,
        "access_token": settings.META_ACCESS_TOKEN,
    }


def _build_client(account_context: dict | None):
    context = account_context or _fallback_account_context()
    if context is None:
        return None
    access_token = context.get("access_token") or settings.META_ACCESS_TOKEN
    phone_number_id = context.get("phone_number_id") or settings.META_PHONE_NUMBER_ID
    if not access_token or not phone_number_id:
        return None
    return build_meta_client(access_token=access_token, phone_number_id=phone_number_id)


async def _report_delivered_usage(*, tenant_id: str, provider_message_id: str) -> None:
    """Best-effort usage ledger for Atende Ai on-demand billing. Never raises to callers."""
    try:
        async with httpx.AsyncClient(timeout=settings.BACKEND_API_TIMEOUT) as client:
            response = await client.post(
                f"{settings.BACKEND_API_URL}/api/v1/internal/usage/delivered",
                headers={"x-internal-api-key": settings.BACKEND_INTERNAL_API_KEY},
                json={
                    "tenant_id": tenant_id,
                    "provider_message_id": provider_message_id,
                    "market": "BR",
                    "quantity": 1,
                },
            )
        if response.status_code >= 400:
            logger.warning(
                "Usage delivered report failed status=%s body=%s",
                response.status_code,
                response.text[:300],
            )
    except Exception as exc:  # noqa: BLE001 — billing must not break webhook
        logger.warning("Usage delivered report error: %s", exc)


async def forward_to_backend(message: NormalizedMessage, account_context: dict | None):
    try:
        async with httpx.AsyncClient(timeout=settings.BACKEND_API_TIMEOUT) as client:
            response = await client.post(
                f"{settings.BACKEND_API_URL}/api/v1/messages/incoming",
                headers={"x-internal-api-key": settings.BACKEND_INTERNAL_API_KEY},
                json=message.model_dump(mode="json"),
            )

        if response.status_code != 200:
            logger.error("Backend returned error: %s - %s", response.status_code, response.text)
            return

        logger.info("Message forwarded to backend: %s", message.message_id)
        action = response.json()
        reply_text = action.get("reply_text") if isinstance(action, dict) else None
        metadata = action.get("metadata") if isinstance(action, dict) else None
        reply_to = normalize_whatsapp_to(
            (action.get("phone_number") if isinstance(action, dict) else None) or message.phone_number
        )
        if not reply_text:
            return

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

        send_client = _build_client(account_context)
        if send_client is None:
            logger.error("No WhatsApp account configured to send reply")
            return
        send_result = await send_client.send_text_message(OutgoingTextMessage(to=reply_to, text=str(reply_text)))
        if send_result.success:
            logger.info("Reply sent to WhatsApp for message %s", message.message_id)
        else:
            logger.error("Failed to send WhatsApp reply for %s: %s", message.message_id, send_result.error)
    except httpx.RequestError as exc:
        logger.error("Failed to forward message to backend: %s", exc)
    except Exception as exc:
        logger.error("Unexpected error forwarding to backend: %s", exc)


async def _handle_coexistence_event(field: str, value: dict | None) -> None:
    if not isinstance(value, dict):
        logger.info("Coexistence webhook field=%s ignored (empty value)", field)
        return
    logger.info("Coexistence webhook field=%s keys=%s", field, list(value.keys()))
    if field == "smb_message_echoes":
        messages = value.get("message_echoes") or value.get("messages") or []
        logger.info("Coexistence message echoes count=%s", len(messages) if isinstance(messages, list) else 0)
    elif field == "history":
        history = value.get("history") or value.get("messages") or []
        logger.info("Coexistence history chunks=%s", len(history) if isinstance(history, list) else 0)
    elif field == "smb_app_state_sync":
        contacts = value.get("contacts") or value.get("state") or []
        logger.info("Coexistence app state sync items=%s", len(contacts) if isinstance(contacts, list) else 0)
    elif field == "account_update":
        event = value.get("event") or value.get("reason")
        logger.warning("Coexistence account_update event=%s payload=%s", event, value)


def _verify_webhook_signature(raw_body: bytes, signature_header: str | None) -> bool:
    secret = (settings.META_APP_SECRET or "").strip()
    if not secret:
        return True
    if not signature_header or not signature_header.startswith("sha256="):
        return False
    expected = hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(signature_header[7:], expected)


async def process_webhook_message(message, metadata, contacts, tenant_id: str, account_context: dict | None):
    try:
        client = _build_client(account_context)
        if client is not None:
            await client.mark_as_read(message.id)
        normalized = normalize_message(message, metadata, contacts, tenant_id)
        logger.info(
            "Processing message: %s from %s type: %s",
            normalized.message_id,
            normalized.phone_number,
            normalized.message_type,
        )
        await forward_to_backend(normalized, account_context)
    except Exception as exc:
        logger.error("Error processing message: %s", exc)


@router.get("/webhook")
async def verify_webhook(
    hub_mode: str = Query(None, alias="hub.mode"),
    hub_verify_token: str = Query(None, alias="hub.verify_token"),
    hub_challenge: str = Query(None, alias="hub.challenge"),
):
    logger.info("Webhook verification: mode=%s", hub_mode)
    if hub_mode == "subscribe":
        if hub_verify_token == settings.META_VERIFY_TOKEN or await _validate_verify_token(hub_verify_token or ""):
            logger.info("Webhook verified successfully")
            return PlainTextResponse(content=hub_challenge or "")
    logger.warning("Webhook verification failed")
    raise HTTPException(status_code=403, detail="Verification failed")


@router.post("/webhook")
async def receive_webhook(
    request: Request,
    background_tasks: BackgroundTasks,
    tenant_id: str = Query(default=None),
):
    try:
        raw_body = await request.body()
        if not _verify_webhook_signature(raw_body, request.headers.get("X-Hub-Signature-256")):
            logger.warning("Webhook signature verification failed")
            raise HTTPException(status_code=403, detail="Invalid signature")

        body = json.loads(raw_body.decode("utf-8"))
        if body.get("object") != "whatsapp_business_account":
            logger.warning("Unknown webhook object: %s", body.get("object"))
            return {"status": "ignored"}

        from schemas import WebhookContact, WebhookMetadata, WebhookMessage

        for entry in body.get("entry") or []:
            for change in entry.get("changes") or []:
                field = change.get("field")
                value = change.get("value") or {}

                if field in {"history", "smb_message_echoes", "smb_app_state_sync", "account_update"}:
                    background_tasks.add_task(_handle_coexistence_event, field, value)
                    continue

                if field != "messages":
                    continue

                metadata = value.get("metadata") or {}
                phone_number_id = metadata.get("phone_number_id")
                account_context = None
                if phone_number_id:
                    account_context = await _resolve_account_context(phone_number_id=phone_number_id)
                status_tenant = (
                    (account_context or {}).get("tenant_id")
                    or tenant_id
                    or settings.DEFAULT_TENANT_ID
                )

                for status_item in value.get("statuses") or []:
                    if not isinstance(status_item, dict):
                        continue
                    errors = status_item.get("errors") or []
                    error_summary = None
                    if errors and isinstance(errors[0], dict):
                        error_summary = (
                            f"#{errors[0].get('code')} {errors[0].get('title') or errors[0].get('message')}"
                        )
                    status_value = str(status_item.get("status") or "").lower()
                    logger.info(
                        "Webhook delivery status recipient=%s message_id=%s status=%s error=%s",
                        status_item.get("recipient_id"),
                        status_item.get("id"),
                        status_value,
                        error_summary,
                    )
                    if status_value == "delivered" and status_item.get("id"):
                        background_tasks.add_task(
                            _report_delivered_usage,
                            tenant_id=status_tenant,
                            provider_message_id=str(status_item.get("id")),
                        )

                messages = value.get("messages") or []
                if not messages:
                    continue

                if not phone_number_id:
                    continue

                logger.info(
                    "Webhook message metadata phone_number_id=%s display_phone_number=%s resolved_tenant=%s resolved_account=%s",
                    phone_number_id,
                    metadata.get("display_phone_number"),
                    (account_context or {}).get("tenant_id"),
                    (account_context or {}).get("account_key"),
                )
                current_tenant = status_tenant

                if account_context is None:
                    account_context = _fallback_account_context(
                        tenant_id=current_tenant,
                        phone_number_id=phone_number_id,
                    )

                parsed_metadata = WebhookMetadata(
                    display_phone_number=str(metadata.get("display_phone_number") or ""),
                    phone_number_id=str(phone_number_id),
                )
                contacts_raw = value.get("contacts") or []
                contacts = [
                    WebhookContact(wa_id=str(item.get("wa_id") or ""), profile=item.get("profile"))
                    for item in contacts_raw
                    if isinstance(item, dict)
                ]

                for message_data in messages:
                    if not isinstance(message_data, dict):
                        continue
                    message = WebhookMessage(**message_data)
                    background_tasks.add_task(
                        process_webhook_message,
                        message,
                        parsed_metadata,
                        contacts,
                        current_tenant,
                        account_context,
                    )

        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Error processing webhook: %s", exc)
        return {"status": "error", "message": str(exc)}


class SendMessageRequest(BaseModel):
    tenant_id: str | None = None
    to: str
    text: str
    phone_number_id: str | None = None


class SendTemplateRequest(BaseModel):
    tenant_id: str | None = None
    to: str
    template_name: str
    language_code: str = "pt_BR"
    phone_number_id: str | None = None
    components: list[dict] | None = None


@router.post("/send-message")
async def send_message(body: SendMessageRequest, request: Request):
    _assert_internal_api(request)
    if not body.to or not body.text:
        raise HTTPException(status_code=422, detail="to and text are required")

    account_context = await _resolve_account_context(
        tenant_id=body.tenant_id,
        phone_number_id=body.phone_number_id,
    )
    if account_context is None:
        account_context = _fallback_account_context(
            tenant_id=body.tenant_id,
            phone_number_id=body.phone_number_id,
        )
    client = _build_client(account_context)
    if client is None:
        raise HTTPException(status_code=502, detail="No WhatsApp account configured")

    result = await client.send_text_message(OutgoingTextMessage(to=body.to, text=body.text))
    if not result.success:
        raise HTTPException(status_code=502, detail=f"Meta API error: {result.error}")
    return {"ok": True, "message_id": result.message_id}


@router.post("/send-template")
async def send_template(body: SendTemplateRequest, request: Request):
    _assert_internal_api(request)
    if not body.to or not body.template_name:
        raise HTTPException(status_code=422, detail="to and template_name are required")

    account_context = await _resolve_account_context(
        tenant_id=body.tenant_id,
        phone_number_id=body.phone_number_id,
    )
    if account_context is None:
        account_context = _fallback_account_context(
            tenant_id=body.tenant_id,
            phone_number_id=body.phone_number_id,
        )
    client = _build_client(account_context)
    if client is None:
        raise HTTPException(status_code=502, detail="No WhatsApp account configured")

    result = await client.send_template_message(
        OutgoingTemplateMessage(
            to=body.to,
            template_name=body.template_name,
            language_code=body.language_code,
            components=body.components,
        )
    )
    if not result.success:
        raise HTTPException(status_code=502, detail=f"Meta API error: {result.error}")
    return {"ok": True, "message_id": result.message_id}


@router.get("/health", response_model=HealthResponse)
async def health_check():
    return HealthResponse(
        status="healthy",
        service=settings.APP_NAME,
        version=settings.APP_VERSION,
        timestamp=datetime.utcnow(),
    )


def _assert_internal_api(request: Request) -> None:
    provided = request.headers.get("x-internal-api-key", "")
    if provided != settings.BACKEND_INTERNAL_API_KEY:
        raise HTTPException(status_code=403, detail="Internal access denied")

