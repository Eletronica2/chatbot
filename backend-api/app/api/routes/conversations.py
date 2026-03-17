"""Conversation monitoring endpoints for admin panel"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Tuple

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.config.settings import settings
from app.services.dependencies import session_service_dependency
from app.services.session_service import SessionService

router = APIRouter(prefix="/api/v1/conversations", tags=["Conversations"])


@router.get("")
async def list_conversations(
    request: Request,
    session_service: SessionService = Depends(session_service_dependency),
) -> List[Dict[str, Any]]:
    tenant_id = getattr(request.state, "tenant_id", "default")
    sessions = await session_service.list_sessions()

    rows: List[Dict[str, Any]] = []
    for session in sessions:
        if session.tenant_id != tenant_id:
            continue

        context = session.context or {}
        rows.append(
            {
                "id": session.key,
                "tenant_id": session.tenant_id,
                "phone_number": session.phone_number,
                "last_message": context.get("last_message", ""),
                "updated_at": session.updated_at.isoformat(),
                "unread_count": int(context.get("unread_count", 0) or 0),
                "ai_enabled": True,
            }
        )

    rows.sort(key=lambda item: item.get("updated_at", ""), reverse=True)
    return rows


@router.get("/{conversation_id}/messages")
async def get_conversation_messages(
    conversation_id: str,
    request: Request,
    session_service: SessionService = Depends(session_service_dependency),
) -> List[Dict[str, Any]]:
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    _assert_tenant_access(request, tenant_id)

    session = await session_service.get_or_create_session(tenant_id, phone_number)
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
    request: Request,
    session_service: SessionService = Depends(session_service_dependency),
) -> Dict[str, Any]:
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    _assert_tenant_access(request, tenant_id)

    session = await session_service.get_or_create_session(tenant_id, phone_number)
    state = session.conversation_state or {}

    return {
        "flow_name": state.get("active_flow") or state.get("last_flow") or "start",
        "current_state": state.get("last_state") or "greeting",
        "state_data": state,
        "updated_at": session.updated_at.isoformat(),
    }


class ReplyRequest(BaseModel):
    text: str


@router.post("/{conversation_id}/reply")
async def send_reply(
    conversation_id: str,
    body: ReplyRequest,
    request: Request,
    session_service: SessionService = Depends(session_service_dependency),
) -> Dict[str, Any]:
    """Send a reply from admin panel agent to a WhatsApp conversation."""
    tenant_id, phone_number = _parse_conversation_id(conversation_id)
    _assert_tenant_access(request, tenant_id)

    text = body.text.strip()
    if not text:
        raise HTTPException(status_code=422, detail="text cannot be empty")

    # Deliver via gateway
    try:
        async with httpx.AsyncClient(timeout=settings.GATEWAY_API_TIMEOUT) as client:
            gw_resp = await client.post(
                f"{settings.GATEWAY_API_URL}/send-message",
                json={"to": phone_number, "text": text},
            )
        if gw_resp.status_code != 200:
            raise HTTPException(status_code=502, detail=f"Gateway error: {gw_resp.text}")
    except httpx.RequestError as exc:
        raise HTTPException(status_code=502, detail=f"Gateway unreachable: {exc}")

    # Record in session history
    session = await session_service.get_or_create_session(tenant_id, phone_number)
    context: Dict[str, Any] = session.context or {}
    messages = context.get("messages")
    if not isinstance(messages, list):
        messages = []
    messages.append({
        "id": str(len(messages) + 1),
        "role": "assistant",
        "content": text,
        "created_at": datetime.utcnow().isoformat(),
    })
    context["messages"] = messages[-50:]
    context["last_message"] = text
    context["last_role"] = "assistant"
    context["updated_at"] = datetime.utcnow().isoformat()
    session.context = context
    await session_service.update_session(session)

    return {"ok": True, "phone_number": phone_number}


def _parse_conversation_id(conversation_id: str) -> Tuple[str, str]:
    if ":" not in conversation_id:
        raise HTTPException(status_code=400, detail="Invalid conversation_id")
    tenant_id, phone_number = conversation_id.split(":", 1)
    if not tenant_id or not phone_number:
        raise HTTPException(status_code=400, detail="Invalid conversation_id")
    return tenant_id, phone_number


def _assert_tenant_access(request: Request, tenant_id: str) -> None:
    request_tenant = getattr(request.state, "tenant_id", "default")
    if tenant_id != request_tenant:
        raise HTTPException(status_code=403, detail="Conversation does not belong to tenant")


def _safe_iso_datetime(raw: Any) -> str:
    if isinstance(raw, str):
        return raw
    return datetime.utcnow().isoformat()
