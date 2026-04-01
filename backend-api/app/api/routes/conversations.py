"""Conversation monitoring endpoints for admin panel."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Tuple

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.api.access import assert_tenant_access, resolve_tenant_scope
from app.config.settings import settings
from app.domain.auth import AuthenticatedUser
from app.services.dependencies import authenticated_user_dependency, message_service_dependency, session_service_dependency
from app.services.message_service import MessageService
from app.services.session_service import SessionService

router = APIRouter(prefix="/api/v1/conversations", tags=["Conversations"])


@router.get("")
async def list_conversations(
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    session_service: SessionService = Depends(session_service_dependency),
) -> List[Dict[str, Any]]:
    target_tenant_id = resolve_tenant_scope(user, request)
    sessions = await session_service.list_sessions()

    rows: List[Dict[str, Any]] = []
    for session in sessions:
        if session.tenant_id != target_tenant_id:
            continue

        context = session.context or {}
        history = session.conversation_history or []
        last_history_message = history[-1].content if history else None
        rows.append(
            {
                "id": session.key,
                "session_id": session.session_id,
                "tenant_id": session.tenant_id,
                "phone_number": session.phone_number,
                "last_message": last_history_message or context.get("last_message", ""),
                "updated_at": session.last_interaction.isoformat(),
                "unread_count": int(context.get("unread_count", 0) or 0),
                "ai_enabled": True,
                "detected_intent": session.detected_intent,
                "display_phone_number": session.display_phone_number,
                "phone_number_id": session.phone_number_id,
            }
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
    stored = await message_service.list_messages(tenant_id=tenant_id, session_id=session.session_id, limit=200)
    if stored:
        return [
            {
                "id": str(item.get("id") or index),
                "role": str(item.get("role") or "user"),
                "content": str(item.get("content") or ""),
                "created_at": _safe_iso_datetime(item.get("created_at")),
            }
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
        "flow_name": session.active_flow or state.get("active_flow") or state.get("last_flow") or "start",
        "current_state": session.current_state or state.get("last_state") or "greeting",
        "state_data": state,
        "updated_at": session.last_interaction.isoformat(),
        "detected_intent": session.detected_intent,
    }


class ReplyRequest(BaseModel):
    text: str


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

    try:
        async with httpx.AsyncClient(timeout=settings.GATEWAY_API_TIMEOUT) as client:
            gw_resp = await client.post(
                f"{settings.GATEWAY_API_URL}/send-message",
                headers={"x-internal-api-key": settings.INTERNAL_API_KEY},
                json={
                    "tenant_id": tenant_id,
                    "to": phone_number,
                    "text": text,
                    "phone_number_id": session.phone_number_id,
                },
            )
        if gw_resp.status_code != 200:
            raise HTTPException(status_code=502, detail=f"Gateway error: {gw_resp.text}")
    except httpx.RequestError as exc:
        raise HTTPException(status_code=502, detail=f"Gateway unreachable: {exc}")

    context: Dict[str, Any] = session.context or {}
    session.append_history(role="assistant", content=text, limit=10)
    messages = [
        {
            "id": str(index),
            "role": item.role,
            "content": item.content,
            "created_at": item.created_at.isoformat(),
        }
        for index, item in enumerate(session.conversation_history, start=1)
    ]
    context["messages"] = messages[-50:]
    context["last_message"] = text
    context["last_role"] = "assistant"
    context["updated_at"] = datetime.utcnow().isoformat()
    session.context = context
    session = await session_service.update_session(session)
    await message_service.append(
        tenant_id=tenant_id,
        session_id=session.session_id,
        direction="outgoing",
        role="assistant",
        content=text,
        source="human",
        metadata={"source": "admin_panel"},
        phone_number_id=session.phone_number_id,
    )

    return {"ok": True, "phone_number": phone_number}


def _parse_conversation_id(conversation_id: str) -> Tuple[str, str]:
    if ":" not in conversation_id:
        raise HTTPException(status_code=400, detail="Invalid conversation_id")
    tenant_id, phone_number = conversation_id.split(":", 1)
    if not tenant_id or not phone_number:
        raise HTTPException(status_code=400, detail="Invalid conversation_id")
    return tenant_id, phone_number
def _safe_iso_datetime(raw: Any) -> str:
    if isinstance(raw, str):
        return raw
    if isinstance(raw, datetime):
        return raw.isoformat()
    return datetime.utcnow().isoformat()

