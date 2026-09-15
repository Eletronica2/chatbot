"""Conversation monitoring and operational inbox endpoints."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from app.api.access import assert_tenant_access, resolve_tenant_scope
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
from app.services.session_service import SessionService
from app.services.tenant_user_service import TenantUserService

router = APIRouter(prefix="/api/v1/conversations", tags=["Conversations"])


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
        "flow_name": session.active_flow or state.get("active_flow") or state.get("last_flow"),
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

    context: Dict[str, Any] = dict(session.context or {})
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
        metadata={"source": "admin_panel", "actor_user_id": user.user_id},
        phone_number_id=session.phone_number_id,
    )

    return {"ok": True, "phone_number": phone_number}


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
