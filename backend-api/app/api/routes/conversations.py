"""Conversation monitoring and operational inbox endpoints."""
from __future__ import annotations

import json
import mimetypes
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple
from uuid import uuid4

import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field

from app.api.access import assert_tenant_access, is_tenant_admin, resolve_tenant_scope
from app.config.settings import settings
from app.domain.auth import AuthenticatedUser
from app.services.admin_audit_service import AdminAuditService
from app.services.conversation_group_service import ConversationGroupService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    conversation_group_service_dependency,
    message_service_dependency,
    session_service_dependency,
    tenant_user_service_dependency,
)
from app.services.message_service import MessageService
from app.services.outbound_billing import finalize_outbound, gateway_billing_fields, reserve_outbound
from app.services.session_service import SessionService
from app.services.tenant_user_service import TenantUserService
from app.utils.inbox_visibility import (
    customer_last_message_at,
    hide_from_inbox,
    outside_service_window,
)
from app.utils.phone_utils import normalize_whatsapp_phone

router = APIRouter(prefix="/api/v1/conversations", tags=["Conversations"])

SERVICE_WINDOW = timedelta(hours=24)
_DELIVERY_ERROR_HINTS = {
    "131047": "A Meta recusou a entrega (janela de 24h ou reengajamento). Peça uma mensagem do cliente ou use template.",
}


def _parse_metadata(raw: Any) -> dict[str, Any]:
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str) and raw.strip():
        try:
            parsed = json.loads(raw)
            return parsed if isinstance(parsed, dict) else {}
        except json.JSONDecodeError:
            return {}
    return {}


def _message_payload(
    *,
    conversation_id: str,
    item: dict[str, Any],
    index: int,
) -> dict[str, Any]:
    meta = _parse_metadata(item.get("metadata"))
    message_type = str(meta.get("message_type") or "text").lower()
    media_id = str(meta.get("media_id") or "").strip()
    row_id = str(item.get("id") or index)
    payload: dict[str, Any] = {
        "id": row_id,
        "role": str(item.get("role") or "user"),
        "content": str(item.get("content") or ""),
        "created_at": _safe_iso_datetime(item.get("created_at")),
        "message_type": message_type,
        "source": str(item.get("source") or meta.get("source") or ""),
    }
    if media_id:
        payload["media_id"] = media_id
        payload["media_mime_type"] = meta.get("media_mime_type")
        payload["media_url"] = f"/api/v1/conversations/{conversation_id}/messages/{row_id}/media"
    filename = meta.get("filename")
    if filename:
        payload["filename"] = filename
    if str(meta.get("delivery_status") or "").lower() == "failed":
        code = str(meta.get("delivery_error_code") or "")
        payload["delivery_failed"] = True
        payload["delivery_error_code"] = code
        payload["delivery_error_hint"] = _DELIVERY_ERROR_HINTS.get(code) or (
            "A Meta não entregou esta mensagem no WhatsApp do cliente."
        )
    return payload


async def _assert_service_window(
    *,
    message_service: MessageService,
    tenant_id: str,
    session_id: str,
) -> None:
    last = await message_service.last_incoming_at(tenant_id=tenant_id, session_id=session_id)
    if last is None:
        raise HTTPException(
            status_code=422,
            detail="Não há mensagem recente do cliente. Aguarde o cliente escrever ou use um template aprovado.",
        )
    if datetime.utcnow() - last > SERVICE_WINDOW:
        raise HTTPException(
            status_code=422,
            detail="Janela de atendimento de 24h expirou. Use template ou aguarde nova mensagem do cliente.",
        )


async def _mark_session_read(
    session,
    *,
    session_service: SessionService,
    group_service: ConversationGroupService | None = None,
    tenant_user_service: TenantUserService | None = None,
) -> Dict[str, Any]:
    context = dict(session.context or {})
    changed = False
    if int(context.get("unread_count", 0) or 0) > 0:
        context["unread_count"] = 0
        changed = True
    if changed:
        session.context = context
        session = await session_service.update_session(session)
    group_name = None
    assigned_name = None
    if group_service and session.group_id:
        groups = await _group_lookup(group_service, session.tenant_id)
        group_name = groups.get(str(session.group_id))
    if tenant_user_service and session.assigned_user_id:
        users = await _user_name_lookup(tenant_user_service, session.tenant_id)
        assigned_name = users.get(str(session.assigned_user_id))
    return _serialize_conversation(session, group_name=group_name, assigned_user_name=assigned_name)


class TransferPayload(BaseModel):
    user_id: str = Field(..., min_length=1)


class GroupPatchPayload(BaseModel):
    group_id: Optional[str] = None


def _assignment_mode(session) -> str:
    mode = str(getattr(session, "assignment_mode", None) or "").strip().lower()
    if mode in {"ai", "human"}:
        return mode
    context = session.context or {}
    legacy = str(context.get("assignment_mode") or "").strip().lower()
    if legacy in {"ai", "human"}:
        return legacy
    if bool(context.get("human_handoff_pending")):
        return "human"
    return "ai"


def _serialize_conversation(
    session,
    *,
    group_name: str | None = None,
    assigned_user_name: str | None = None,
) -> Dict[str, Any]:
    context = session.context or {}
    history = session.conversation_history or []
    last_history_message = history[-1].content if history else None
    assignment_mode = _assignment_mode(session)
    human_handoff_pending = assignment_mode == "human" or bool(context.get("human_handoff_pending"))
    assigned_user_id = getattr(session, "assigned_user_id", None) or context.get("assigned_user_id")
    group_id = getattr(session, "group_id", None) or context.get("group_id")
    name = assigned_user_name or context.get("assigned_user_name")
    gname = group_name or context.get("group_name") or ("Geral" if assignment_mode else None)
    return {
        "id": (
            session.key
            if (session.phone_number or "").strip()
            else f"{session.tenant_id}:_"
        ),
        "session_id": session.session_id,
        "tenant_id": session.tenant_id,
        "phone_number": session.phone_number,
        "last_message": last_history_message or context.get("last_message", ""),
        "updated_at": session.last_interaction.isoformat(),
        "unread_count": int(context.get("unread_count", 0) or 0),
        "ai_enabled": assignment_mode == "ai",
        "human_handoff_pending": human_handoff_pending,
        "human_handoff_reason": context.get("human_handoff_reason"),
        "assignment_mode": assignment_mode,
        "assigned_user_id": assigned_user_id,
        "assigned_user_name": name,
        "group_id": group_id,
        "group_name": gname,
        "detected_intent": session.detected_intent,
        "display_phone_number": session.display_phone_number,
        "phone_number_id": session.phone_number_id,
    }


async def _group_lookup(
    group_service: ConversationGroupService,
    tenant_id: str,
) -> Dict[str, str]:
    groups = await group_service.list_groups(tenant_id)
    return {str(g["id"]): str(g["name"]) for g in groups}


async def _user_name_lookup(
    tenant_user_service: TenantUserService,
    tenant_id: str,
) -> Dict[str, str]:
    try:
        users = await tenant_user_service.list_users(tenant_id)
    except Exception:
        return {}
    result: Dict[str, str] = {}
    for item in users:
        uid = str(getattr(item, "user_id", "") or "")
        if uid:
            result[uid] = str(getattr(item, "display_name", "") or getattr(item, "email", "") or uid)
    return result


@router.get("")
async def list_conversations(
    request: Request,
    filter: Optional[str] = Query(default=None, alias="filter"),
    group_id: Optional[str] = Query(default=None),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
    message_service: MessageService = Depends(message_service_dependency),
    group_service: ConversationGroupService = Depends(conversation_group_service_dependency),
    tenant_user_service: TenantUserService = Depends(tenant_user_service_dependency),
) -> List[Dict[str, Any]]:
    target_tenant_id = resolve_tenant_scope(user, request)
    await group_service.ensure_default_group(target_tenant_id)
    sessions = await session_service.list_sessions()
    groups = await _group_lookup(group_service, target_tenant_id)
    users = await _user_name_lookup(tenant_user_service, target_tenant_id)

    filter_key = (filter or "all").strip().lower()
    rows: List[Dict[str, Any]] = []
    for session in sessions:
        if session.tenant_id != target_tenant_id:
            continue
        # Hide legacy simulation phones from operational inbox
        phone = (session.phone_number or "").strip().lower()
        if phone in {"simulation-user", "simulation"} or phone.startswith("sim-"):
            continue

        mode = _assignment_mode(session)
        assigned_user_id = getattr(session, "assigned_user_id", None) or (session.context or {}).get(
            "assigned_user_id"
        )
        sid_group = getattr(session, "group_id", None) or (session.context or {}).get("group_id")

        if filter_key == "mine":
            if str(assigned_user_id or "") != str(user.user_id):
                continue
        elif filter_key == "ai":
            if mode != "ai":
                continue
        elif filter_key == "human":
            if mode != "human":
                continue

        if group_id and str(sid_group or "") != str(group_id):
            continue

        context = dict(session.context or {})
        if context.get("inbox_hidden"):
            continue

        last_customer = customer_last_message_at(context)
        if last_customer is None:
            last_customer = await message_service.last_incoming_at(
                tenant_id=target_tenant_id,
                session_id=session.session_id,
            )
            if last_customer is not None:
                context["last_customer_message_at"] = last_customer.isoformat()
                session.context = context
                session = await session_service.update_session(session)

        if last_customer is not None and outside_service_window(last_customer):
            session.context = hide_from_inbox(context, reason="service_window_expired")
            await session_service.update_session(session)
            continue
        if last_customer is None:
            last_touch = session.last_interaction
            if last_touch is not None and outside_service_window(
                last_touch.replace(tzinfo=None) if getattr(last_touch, "tzinfo", None) else last_touch
            ):
                session.context = hide_from_inbox(context, reason="service_window_expired")
                await session_service.update_session(session)
            continue

        rows.append(
            _serialize_conversation(
                session,
                group_name=groups.get(str(sid_group or "")),
                assigned_user_name=users.get(str(assigned_user_id or "")),
            )
        )

    rows.sort(key=lambda item: item.get("updated_at", ""), reverse=True)
    return rows


@router.get("/{conversation_id}/messages")
async def get_conversation_messages(
    conversation_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
    message_service: MessageService = Depends(message_service_dependency),
) -> List[Dict[str, Any]]:
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    assert_tenant_access(user, tenant_id)

    session = await session_service.get_or_create_session(tenant_id, phone_number)
    context = dict(session.context or {})
    if int(context.get("unread_count", 0) or 0) > 0:
        context["unread_count"] = 0
        session.context = context
        session = await session_service.update_session(session)
    stored = await message_service.list_messages(tenant_id=tenant_id, session_id=session.session_id, limit=200)
    if stored:
        return [
            _message_payload(conversation_id=conversation_id, item=item, index=index)
            for index, item in enumerate(stored, start=1)
        ]

    if session.conversation_history:
        return [
            {
                "id": str(index),
                "role": item.role,
                "content": item.content,
                "created_at": item.created_at.isoformat(),
            }
            for index, item in enumerate(session.conversation_history, start=1)
        ]

    context = session.context or {}
    messages = context.get("messages")
    if not isinstance(messages, list):
        return []

    normalized: List[Dict[str, Any]] = []
    for index, item in enumerate(messages, start=1):
        if not isinstance(item, dict):
            continue
        normalized.append(
            {
                "id": str(item.get("id") or index),
                "role": str(item.get("role") or "user"),
                "content": str(item.get("content") or ""),
                "created_at": _safe_iso_datetime(item.get("created_at")),
            }
        )
    return normalized


@router.get("/{conversation_id}/flow")
async def get_conversation_flow(
    conversation_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
) -> Dict[str, Any]:
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    assert_tenant_access(user, tenant_id)

    session = await session_service.get_or_create_session(tenant_id, phone_number)
    state = session.conversation_state or {}

    return {
        "flow_name": session.active_flow or state.get("active_flow") or state.get("last_flow"),
        "current_state": session.current_state or state.get("last_state") or "greeting",
        "state_data": state,
        "updated_at": session.last_interaction.isoformat(),
        "detected_intent": session.detected_intent,
    }


class ReplyRequest(BaseModel):
    text: str
    source: Optional[str] = None
    client_message_id: Optional[str] = Field(default=None, max_length=80)


@router.post("/{conversation_id}/reply")
async def send_reply(
    conversation_id: str,
    body: ReplyRequest,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
    message_service: MessageService = Depends(message_service_dependency),
) -> Dict[str, Any]:
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    assert_tenant_access(user, tenant_id)

    text = body.text.strip()
    if not text:
        raise HTTPException(status_code=422, detail="text cannot be empty")

    session = await session_service.get_or_create_session(tenant_id, phone_number)
    await _assert_service_window(
        message_service=message_service,
        tenant_id=tenant_id,
        session_id=session.session_id,
    )

    source_path = "quick_reply" if (body.source or "").strip().lower() == "quick_reply" else "manual"
    billing = await reserve_outbound(
        tenant_id,
        category="SERVICE",
        category_source="freeform_service_reply",
        source_path=source_path,
        idempotency_key=f"{source_path}:{body.client_message_id or uuid4()}",
        phone_number_id=session.phone_number_id,
    )
    provider_message_id: str | None = None
    try:
        async with httpx.AsyncClient(timeout=settings.GATEWAY_API_TIMEOUT) as client:
            gw_resp = await client.post(
                f"{settings.GATEWAY_API_URL}/send-message",
                headers={"x-internal-api-key": settings.INTERNAL_API_KEY},
                json={
                    "tenant_id": tenant_id,
                    "to": normalize_whatsapp_phone(phone_number),
                    "text": text,
                    "phone_number_id": session.phone_number_id,
                    **gateway_billing_fields(billing),
                },
            )
        if gw_resp.status_code != 200:
            raise HTTPException(status_code=502, detail=f"Gateway error: {gw_resp.text}")
        provider_message_id = (gw_resp.json() or {}).get("message_id")
    except httpx.RequestError as exc:
        raise HTTPException(status_code=502, detail=f"Gateway unreachable: {exc}")
    finally:
        await finalize_outbound(tenant_id, billing, provider_message_id=provider_message_id)

    context: Dict[str, Any] = dict(session.context or {})
    session.append_history(role="assistant", content=text, limit=10, source="human")
    messages = [
        {
            "id": str(index),
            "role": item.role,
            "content": item.content,
            "created_at": item.created_at.isoformat(),
            "source": item.source,
        }
        for index, item in enumerate(session.conversation_history, start=1)
    ]
    context["messages"] = messages[-50:]
    context["last_message"] = text
    context["last_role"] = "assistant"
    context["updated_at"] = datetime.utcnow().isoformat()
    context.pop("human_handoff_pending", None)
    context.pop("human_handoff_reason", None)
    context.pop("human_handoff_at", None)
    context["unread_count"] = 0
    # Human reply implies human ownership if still AI
    if _assignment_mode(session) == "ai":
        session.assignment_mode = "human"
        session.assigned_user_id = user.user_id
        context["assignment_mode"] = "human"
        context["assigned_user_id"] = user.user_id
        context["assigned_user_name"] = user.display_name
    session.context = context
    session = await session_service.update_session(session)
    await message_service.append(
        tenant_id=tenant_id,
        session_id=session.session_id,
        direction="outgoing",
        role="assistant",
        content=text,
        source="human",
        metadata={
            "source": "admin_panel",
            "actor_user_id": user.user_id,
            "provider_message_id": provider_message_id,
            "billing_reservation_id": billing.get("billing_reservation_id"),
        },
        phone_number_id=session.phone_number_id,
    )

    return {"ok": True, "phone_number": phone_number, "billing_level": billing.get("billing_level")}


def _media_kind(mime_type: str, filename: str) -> str:
    mime = (mime_type or "").lower()
    if mime.startswith("image/"):
        return "image"
    if mime.startswith("audio/"):
        return "audio"
    if mime.startswith("video/"):
        return "video"
    if filename.lower().endswith((".jpg", ".jpeg", ".png", ".webp", ".gif")):
        return "image"
    return "document"


@router.get("/{conversation_id}/messages/{message_db_id}/media")
async def download_conversation_media(
    conversation_id: str,
    message_db_id: int,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
    message_service: MessageService = Depends(message_service_dependency),
):
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    assert_tenant_access(user, tenant_id)
    session = await session_service.get_or_create_session(tenant_id, phone_number)
    row = await message_service.get_message(
        tenant_id=tenant_id,
        session_id=session.session_id,
        message_id=message_db_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail="message not found")
    meta = _parse_metadata(row.get("metadata"))
    media_id = str(meta.get("media_id") or "").strip()
    if not media_id:
        raise HTTPException(status_code=404, detail="no media on message")
    phone_number_id = row.get("phone_number_id") or session.phone_number_id
    async with httpx.AsyncClient(timeout=settings.GATEWAY_API_TIMEOUT) as client:
        gw_resp = await client.post(
            f"{settings.GATEWAY_API_URL}/fetch-media",
            headers={"x-internal-api-key": settings.INTERNAL_API_KEY},
            json={
                "tenant_id": tenant_id,
                "phone_number_id": phone_number_id,
                "media_id": media_id,
            },
        )
    if gw_resp.status_code != 200:
        raise HTTPException(status_code=502, detail="Não foi possível carregar a mídia")
    mime = str(meta.get("media_mime_type") or gw_resp.headers.get("content-type") or "application/octet-stream")
    return Response(content=gw_resp.content, media_type=mime)


@router.post("/{conversation_id}/reply-media")
async def send_reply_media(
    conversation_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
    message_service: MessageService = Depends(message_service_dependency),
    caption: str = Form(""),
    media_type: str = Form(""),
    file: UploadFile = File(...),
):
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    assert_tenant_access(user, tenant_id)
    session = await session_service.get_or_create_session(tenant_id, phone_number)
    await _assert_service_window(
        message_service=message_service,
        tenant_id=tenant_id,
        session_id=session.session_id,
    )
    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=422, detail="empty file")
    filename = file.filename or "upload"
    mime = (file.content_type or mimetypes.guess_type(filename)[0] or "application/octet-stream").strip()
    kind = (media_type or _media_kind(mime, filename)).strip().lower()

    billing = await reserve_outbound(
        tenant_id,
        category="SERVICE",
        category_source="freeform_service_reply",
        source_path="manual_media",
        idempotency_key=f"manual_media:{uuid4()}",
        phone_number_id=session.phone_number_id,
    )
    provider_message_id: str | None = None
    uploaded_media_id: str | None = None
    try:
        data = {
            "tenant_id": tenant_id,
            "to": normalize_whatsapp_phone(phone_number),
            "phone_number_id": session.phone_number_id or "",
            "media_type": kind,
            "caption": caption.strip(),
            "filename": filename,
            **gateway_billing_fields(billing),
        }
        if not data.get("billing_reservation_id"):
            data["billing_enforced"] = "false"
        async with httpx.AsyncClient(timeout=settings.GATEWAY_API_TIMEOUT) as client:
            gw_resp = await client.post(
                f"{settings.GATEWAY_API_URL}/send-media",
                headers={"x-internal-api-key": settings.INTERNAL_API_KEY},
                data=data,
                files={"file": (filename, raw, mime)},
            )
        if gw_resp.status_code != 200:
            raise HTTPException(status_code=502, detail="Não foi possível enviar a mídia")
        body = gw_resp.json() or {}
        provider_message_id = body.get("message_id")
        uploaded_media_id = body.get("media_id")
    except httpx.RequestError as exc:
        raise HTTPException(status_code=502, detail=f"Gateway unreachable: {exc}") from exc
    finally:
        await finalize_outbound(tenant_id, billing, provider_message_id=provider_message_id)

    cap = caption.strip()
    label = cap if cap else {
        "image": "[Imagem enviada]",
        "audio": "[Áudio enviado]",
        "video": "[Vídeo enviado]",
        "document": f"[Documento: {filename}]",
    }.get(kind, "[Mídia enviada]")
    context: Dict[str, Any] = dict(session.context or {})
    session.append_history(role="assistant", content=label, limit=10, source="human")
    if _assignment_mode(session) == "ai":
        session.assignment_mode = "human"
        session.assigned_user_id = user.user_id
        context["assignment_mode"] = "human"
        context["assigned_user_id"] = user.user_id
        context["assigned_user_name"] = user.display_name
    context.pop("human_handoff_pending", None)
    context.pop("human_handoff_reason", None)
    context.pop("human_handoff_at", None)
    context["unread_count"] = 0
    context["last_message"] = label
    context["last_role"] = "assistant"
    context["updated_at"] = datetime.utcnow().isoformat()
    session.context = context
    session = await session_service.update_session(session)
    await message_service.append(
        tenant_id=tenant_id,
        session_id=session.session_id,
        direction="outgoing",
        role="assistant",
        content=label,
        source="human",
        metadata={
            "source": "admin_panel",
            "actor_user_id": user.user_id,
            "message_type": kind,
            "media_id": uploaded_media_id,
            "media_mime_type": mime,
            "filename": filename,
            "caption": cap,
            "provider_message_id": provider_message_id,
            "billing_reservation_id": billing.get("billing_reservation_id"),
        },
        phone_number_id=session.phone_number_id,
        external_message_id=provider_message_id,
    )
    return {
        "ok": True,
        "message_type": kind,
        "content": label,
        "caption": cap,
        "provider_message_id": provider_message_id,
    }


@router.post("/{conversation_id}/finalize")
async def finalize_conversation(
    conversation_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
    group_service: ConversationGroupService = Depends(conversation_group_service_dependency),
    tenant_user_service: TenantUserService = Depends(tenant_user_service_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> Dict[str, Any]:
    """Archive thread in the inbox until the customer sends a new inbound message."""
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    assert_tenant_access(user, tenant_id)
    session = await session_service.get_or_create_session(tenant_id, phone_number)

    session.assignment_mode = "ai"
    session.assigned_user_id = None
    context = hide_from_inbox(session.context, reason="agent_finalized")
    context["assignment_mode"] = "ai"
    context.pop("assigned_user_id", None)
    context.pop("assigned_user_name", None)
    session.context = context
    session = await session_service.update_session(session)

    await audit.append(
        tenant_id=tenant_id,
        action="conversation.finalize",
        entity_type="conversation",
        entity_key=conversation_id,
        summary="Atendimento finalizado e removido da fila",
        actor=user,
        metadata={"phone_number": phone_number},
    )
    return await _mark_session_read(
        session,
        session_service=session_service,
        group_service=group_service,
        tenant_user_service=tenant_user_service,
    )


@router.post("/{conversation_id}/mark-read")
async def mark_conversation_read(
    conversation_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
    group_service: ConversationGroupService = Depends(conversation_group_service_dependency),
    tenant_user_service: TenantUserService = Depends(tenant_user_service_dependency),
) -> Dict[str, Any]:
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    assert_tenant_access(user, tenant_id)
    session = await session_service.get_or_create_session(tenant_id, phone_number)
    return await _mark_session_read(
        session,
        session_service=session_service,
        group_service=group_service,
        tenant_user_service=tenant_user_service,
    )


@router.post("/{conversation_id}/assume")
async def assume_conversation(
    conversation_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
    group_service: ConversationGroupService = Depends(conversation_group_service_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> Dict[str, Any]:
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    assert_tenant_access(user, tenant_id)
    session = await session_service.get_or_create_session(tenant_id, phone_number)

    mode = _assignment_mode(session)
    current_assignee = str(getattr(session, "assigned_user_id", None) or (session.context or {}).get("assigned_user_id") or "")
    if mode == "human" and current_assignee and current_assignee != str(user.user_id):
        holder = (session.context or {}).get("assigned_user_name") or current_assignee
        raise HTTPException(
            status_code=409,
            detail=f"Esta conversa foi assumida por {holder}.",
        )

    from_label = "IA" if mode == "ai" else ((session.context or {}).get("assigned_user_name") or current_assignee or "humano")
    session.assignment_mode = "human"
    session.assigned_user_id = user.user_id
    context = dict(session.context or {})
    context["assignment_mode"] = "human"
    context["assigned_user_id"] = user.user_id
    context["assigned_user_name"] = user.display_name
    context["human_handoff_pending"] = True
    context["human_handoff_reason"] = "assumed_by_agent"
    context["human_handoff_at"] = datetime.utcnow().isoformat()
    session.context = context
    session = await session_service.update_session(session)

    await audit.append(
        tenant_id=tenant_id,
        action="conversation.assume",
        entity_type="conversation",
        entity_key=conversation_id,
        summary=f"{from_label} → {user.display_name}",
        actor=user,
        metadata={"from": from_label, "to": user.display_name, "to_user_id": user.user_id},
    )

    groups = await _group_lookup(group_service, tenant_id)
    return _serialize_conversation(
        session,
        group_name=groups.get(str(session.group_id or "")),
        assigned_user_name=user.display_name,
    )


@router.post("/{conversation_id}/transfer")
async def transfer_conversation(
    conversation_id: str,
    payload: TransferPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
    group_service: ConversationGroupService = Depends(conversation_group_service_dependency),
    tenant_user_service: TenantUserService = Depends(tenant_user_service_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> Dict[str, Any]:
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    assert_tenant_access(user, tenant_id)
    session = await session_service.get_or_create_session(tenant_id, phone_number)

    target_id = payload.user_id.strip()
    users = await tenant_user_service.list_users(tenant_id)
    target = next((u for u in users if str(u.user_id) == target_id), None)
    if target is None:
        raise HTTPException(status_code=404, detail="Usuário não encontrado neste tenant")
    status = str(getattr(target, "status", "active") or "active").lower()
    if status != "active":
        raise HTTPException(status_code=400, detail="Usuário de destino não está ativo")

    from_name = (session.context or {}).get("assigned_user_name") or user.display_name
    session.assignment_mode = "human"
    session.assigned_user_id = target_id
    context = dict(session.context or {})
    context["assignment_mode"] = "human"
    context["assigned_user_id"] = target_id
    context["assigned_user_name"] = target.display_name
    context["human_handoff_pending"] = True
    context["human_handoff_reason"] = "transferred"
    session.context = context
    session = await session_service.update_session(session)

    await audit.append(
        tenant_id=tenant_id,
        action="conversation.transfer",
        entity_type="conversation",
        entity_key=conversation_id,
        summary=f"{from_name} → {target.display_name}",
        actor=user,
        metadata={
            "from": from_name,
            "to": target.display_name,
            "to_user_id": target_id,
        },
    )

    groups = await _group_lookup(group_service, tenant_id)
    return _serialize_conversation(
        session,
        group_name=groups.get(str(session.group_id or "")),
        assigned_user_name=target.display_name,
    )


@router.post("/{conversation_id}/return-to-ai")
async def return_conversation_to_ai(
    conversation_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
    group_service: ConversationGroupService = Depends(conversation_group_service_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> Dict[str, Any]:
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    assert_tenant_access(user, tenant_id)
    session = await session_service.get_or_create_session(tenant_id, phone_number)

    from_name = (session.context or {}).get("assigned_user_name") or user.display_name
    session.assignment_mode = "ai"
    session.assigned_user_id = None
    context = dict(session.context or {})
    context["assignment_mode"] = "ai"
    context.pop("assigned_user_id", None)
    context.pop("assigned_user_name", None)
    context.pop("human_handoff_pending", None)
    context.pop("human_handoff_reason", None)
    context.pop("human_handoff_at", None)
    session.context = context
    session = await session_service.update_session(session)

    await audit.append(
        tenant_id=tenant_id,
        action="conversation.return_to_ai",
        entity_type="conversation",
        entity_key=conversation_id,
        summary=f"{from_name} → IA",
        actor=user,
        metadata={"from": from_name, "to": "IA"},
    )

    groups = await _group_lookup(group_service, tenant_id)
    return _serialize_conversation(session, group_name=groups.get(str(session.group_id or "")))


@router.post("/{conversation_id}/reset-state")
async def reset_conversation_state(
    conversation_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> Dict[str, Any]:
    """Start the conversation over: flow step, collected data, order draft and pending handoff are cleared.

    Messages and history are kept; the AI only reads turns after this point.
    """
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    assert_tenant_access(user, tenant_id)
    if not is_tenant_admin(user):
        raise HTTPException(status_code=403, detail="Tenant admin access required")
    session = await session_service.get_or_create_session(tenant_id, phone_number)
    context = dict(session.context or {})
    cleared = {
        "current_state": session.current_state,
        "collected_keys": sorted(((session.conversation_state or {}).get("collected_data") or {}).keys()),
        "had_order_draft": bool(context.get("order_draft")),
        "had_handoff_pending": bool(context.get("human_handoff_pending")),
    }
    session.conversation_state = {}
    session.current_state = None
    for key in ("order_draft", "human_handoff_pending", "human_handoff_reason", "human_handoff_at"):
        context.pop(key, None)
    context["episode_started_at"] = datetime.utcnow().isoformat()
    session.context = context
    await session_service.update_session(session)
    await audit.append(
        tenant_id=tenant_id,
        action="conversation.reset_state",
        entity_type="conversation",
        entity_key=conversation_id,
        summary="Estado transitório da conversa reiniciado (histórico preservado)",
        actor=user,
        metadata=cleared,
    )
    return {"ok": True, "cleared": cleared}


@router.patch("/{conversation_id}/group")
async def set_conversation_group(
    conversation_id: str,
    payload: GroupPatchPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
    group_service: ConversationGroupService = Depends(conversation_group_service_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> Dict[str, Any]:
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    assert_tenant_access(user, tenant_id)
    session = await session_service.get_or_create_session(tenant_id, phone_number)

    default = await group_service.ensure_default_group(tenant_id)
    target_group_id = (payload.group_id or "").strip() or str(default["id"])
    groups = await group_service.list_groups(tenant_id)
    target = next((g for g in groups if str(g["id"]) == target_group_id), None)
    if target is None:
        raise HTTPException(status_code=404, detail="Grupo não encontrado")

    from_group = (session.context or {}).get("group_name") or "Geral"
    session.group_id = target_group_id
    context = dict(session.context or {})
    context["group_id"] = target_group_id
    context["group_name"] = target["name"]
    session.context = context
    session = await session_service.update_session(session)

    await audit.append(
        tenant_id=tenant_id,
        action="conversation.group_change",
        entity_type="conversation",
        entity_key=conversation_id,
        summary=f"Grupo {from_group} → {target['name']}",
        actor=user,
        metadata={"from": from_group, "to": target["name"], "group_id": target_group_id},
    )

    assigned_user_id = session.assigned_user_id or context.get("assigned_user_id")
    return _serialize_conversation(
        session,
        group_name=str(target["name"]),
        assigned_user_name=context.get("assigned_user_name"),
    )


def _parse_conversation_id(conversation_id: str) -> Tuple[str, str]:
    if ":" not in conversation_id:
        raise HTTPException(status_code=400, detail="Invalid conversation_id")
    tenant_id, phone_number = conversation_id.split(":", 1)
    if not tenant_id.strip():
        raise HTTPException(status_code=400, detail="Invalid conversation_id")
    if phone_number == "_":
        phone_number = ""
    return tenant_id, phone_number


def _safe_iso_datetime(raw: Any) -> str:
    if isinstance(raw, str):
        return raw
    if isinstance(raw, datetime):
        return raw.isoformat()
    return datetime.utcnow().isoformat()
