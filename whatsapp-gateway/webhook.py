"""WhatsApp Webhook handlers."""
from __future__ import annotations

import hashlib
import hmac
import json
import logging
from datetime import datetime
from typing import Optional

import httpx
from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, Query, Request, UploadFile
from fastapi.responses import PlainTextResponse, Response
from pydantic import BaseModel

from config import settings
from meta_client import build_meta_client
from phone_utils import normalize_whatsapp_to
from schemas import (
    HealthResponse,
    MessageDirection,
    MessageType,
    NormalizedMessage,
    OutgoingDocumentMessage,
    OutgoingImageMessage,
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


async def _post_internal(path: str, payload: dict) -> bool:
    """Best-effort internal call to the backend billing API. Never raises to callers."""
    try:
        async with httpx.AsyncClient(timeout=settings.BACKEND_API_TIMEOUT) as client:
            response = await client.post(
                f"{settings.BACKEND_API_URL}{path}",
                headers={"x-internal-api-key": settings.BACKEND_INTERNAL_API_KEY},
                json=payload,
            )
        if response.status_code >= 400:
            logger.warning("Internal billing call %s failed status=%s body=%s", path, response.status_code, response.text[:300])
            return False
        return True
    except Exception as exc:  # noqa: BLE001 — billing must not break webhook
        logger.warning("Internal billing call %s error: %s", path, exc)
        return False


async def _report_template_status(
    *,
    waba_id: str,
    entry_time: int,
    value: dict,
) -> None:
    if not isinstance(value, dict):
        return
    event = str(value.get("event") or value.get("status") or "").strip()
    template_ref = value.get("message_template_id") or value.get("message_template_name")
    if not waba_id or not event or template_ref is None:
        logger.info(
            "Template status webhook ignored waba=%s keys=%s",
            waba_id,
            list(value.keys()),
        )
        return
    logger.info(
        "Template status webhook waba=%s template=%s event=%s",
        waba_id,
        template_ref,
        event,
    )
    await _post_internal(
        "/api/v1/internal/whatsapp/template-status",
        {
            "waba_id": waba_id,
            "entry_time": entry_time,
            "value": value,
        },
    )


async def _report_message_status(
    *,
    tenant_id: str,
    provider_message_id: str,
    status: str,
    phone_number_id: str | None,
    pricing: dict | None,
    error_code: str | None,
) -> None:
    pricing = pricing if isinstance(pricing, dict) else {}
    await _post_internal(
        "/api/v1/internal/billing/status",
        {
            "tenant_id": tenant_id,
            "provider_message_id": provider_message_id,
            "status": status,
            "phone_number_id": phone_number_id,
            "pricing_category": pricing.get("category"),
            "pricing_billable": pricing.get("billable"),
            "error_code": error_code,
        },
    )


async def _finalize_reservation(*, tenant_id: str, reservation_id: str, provider_message_id: str | None) -> None:
    if provider_message_id:
        await _post_internal(
            "/api/v1/internal/billing/accepted",
            {"tenant_id": tenant_id, "reservation_id": reservation_id, "provider_message_id": provider_message_id},
        )
    else:
        await _post_internal(
            "/api/v1/internal/billing/release",
            {"tenant_id": tenant_id, "reservation_id": reservation_id, "reason": "send_failed"},
        )


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

        billing = (metadata or {}).get("billing") if isinstance(metadata, dict) else None
        billing = billing if isinstance(billing, dict) else {}
        reservation_id = billing.get("reservation_id")
        if billing.get("enforced") and not reservation_id:
            logger.warning("Reply for %s blocked: billing enforced without reservation", message.message_id)
            return
        billing_tenant = (action.get("tenant_id") if isinstance(action, dict) else None) or message.tenant_id

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
            if reservation_id:
                await _finalize_reservation(tenant_id=billing_tenant, reservation_id=reservation_id, provider_message_id=None)
            return
        send_result = await send_client.send_text_message(OutgoingTextMessage(to=reply_to, text=str(reply_text)))
        if send_result.success:
            logger.info("Reply sent to WhatsApp for message %s", message.message_id)
        else:
            logger.error("Failed to send WhatsApp reply for %s: %s", message.message_id, send_result.error)
        if reservation_id:
            await _finalize_reservation(
                tenant_id=billing_tenant,
                reservation_id=reservation_id,
                provider_message_id=send_result.message_id if send_result.success else None,
            )
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

                if field == "message_template_status_update":
                    waba_id = str(entry.get("id") or "").strip()
                    entry_time = int(entry.get("time") or 0)
                    background_tasks.add_task(
                        _report_template_status,
                        waba_id=waba_id,
                        entry_time=entry_time,
                        value=value if isinstance(value, dict) else {},
                    )
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
                    error_code = None
                    if errors and isinstance(errors[0], dict):
                        error_code = str(errors[0].get("code") or "") or None
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
                    if status_value and status_item.get("id"):
                        background_tasks.add_task(
                            _report_message_status,
                            tenant_id=status_tenant,
                            provider_message_id=str(status_item.get("id")),
                            status=status_value,
                            phone_number_id=phone_number_id,
                            pricing=status_item.get("pricing"),
                            error_code=error_code,
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
    billing_enforced: bool | None = None
    billing_reservation_id: str | None = None


class SendTemplateRequest(BaseModel):
    tenant_id: str | None = None
    to: str
    template_name: str
    language_code: str = "pt_BR"
    phone_number_id: str | None = None
    components: list[dict] | None = None
    billing_enforced: bool | None = None
    billing_reservation_id: str | None = None


def _assert_billing_gate(body: SendMessageRequest | SendTemplateRequest) -> None:
    """Every outbound must carry a BillingGate decision (reservation or explicit non-enforced)."""
    if body.billing_reservation_id:
        return
    if body.billing_enforced is False:
        return
    raise HTTPException(status_code=428, detail="billing gate decision required")


@router.post("/send-message")
async def send_message(body: SendMessageRequest, request: Request):
    _assert_internal_api(request)
    _assert_billing_gate(body)
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


class FetchMediaRequest(BaseModel):
    tenant_id: str | None = None
    phone_number_id: str | None = None
    media_id: str


@router.post("/fetch-media")
async def fetch_media(body: FetchMediaRequest, request: Request):
    _assert_internal_api(request)
    media_id = (body.media_id or "").strip()
    if not media_id:
        raise HTTPException(status_code=422, detail="media_id is required")
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
    media_url = await client.get_media_url(media_id)
    if not media_url:
        raise HTTPException(status_code=404, detail="Media not found")
    payload = await client.download_media(media_url)
    if not payload:
        raise HTTPException(status_code=502, detail="Failed to download media")
    mime = "application/octet-stream"
    if "/" in media_id:
        pass
    return Response(content=payload, media_type=mime)


@router.post("/send-media")
async def send_media(
    request: Request,
    tenant_id: str = Form(""),
    to: str = Form(""),
    phone_number_id: str | None = Form(None),
    media_type: str = Form("image"),
    caption: str = Form(""),
    filename: str = Form("upload"),
    billing_reservation_id: str | None = Form(None),
    billing_enforced: str | None = Form(None),
    file: UploadFile = File(...),
):
    _assert_internal_api(request)
    if not (billing_reservation_id or "").strip() and billing_enforced != "false":
        raise HTTPException(status_code=428, detail="billing gate decision required")

    if not to.strip():
        raise HTTPException(status_code=422, detail="to is required")
    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=422, detail="empty file")
    mime = (file.content_type or "application/octet-stream").strip()
    kind = (media_type or "image").strip().lower()
    account_context = await _resolve_account_context(tenant_id=tenant_id or None, phone_number_id=phone_number_id)
    if account_context is None:
        account_context = _fallback_account_context(tenant_id=tenant_id or None, phone_number_id=phone_number_id)
    client = _build_client(account_context)
    if client is None:
        raise HTTPException(status_code=502, detail="No WhatsApp account configured")

    media_id = await client.upload_media(data=raw, mime_type=mime, filename=filename or file.filename or "upload")
    if not media_id:
        raise HTTPException(status_code=502, detail="Meta media upload failed")

    cap = caption.strip() or None
    if kind == "image":
        result = await client.send_image_message(OutgoingImageMessage(to=to, image_id=media_id, caption=cap))
    elif kind == "document":
        result = await client.send_document_message(
            OutgoingDocumentMessage(to=to, document_id=media_id, filename=filename or file.filename or "arquivo", caption=cap)
        )
    elif kind == "audio":
        result = await client.send_audio_message(to=to, media_id=media_id)
    elif kind == "video":
        result = await client.send_video_message(to=to, media_id=media_id, caption=cap)
    else:
        raise HTTPException(status_code=422, detail="unsupported media_type")
    if not result.success:
        raise HTTPException(status_code=502, detail=f"Meta API error: {result.error}")
    return {"ok": True, "message_id": result.message_id, "media_id": media_id, "media_type": kind}


@router.post("/send-template")
async def send_template(body: SendTemplateRequest, request: Request):
    _assert_internal_api(request)
    _assert_billing_gate(body)
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

