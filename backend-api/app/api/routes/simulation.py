"""Simulation endpoints used by the admin panel preview."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.access import resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.domain.message import ConversationAction, MessageDirection, MessageType, NormalizedMessage
from app.services.conversation_service import ConversationService
from app.services.dependencies import authenticated_user_dependency, conversation_service_dependency

router = APIRouter(tags=["Simulation"])


class SimulationSendPayload(BaseModel):
    tenant_id: str = Field(..., min_length=1)
    message: str = Field(..., min_length=1)
    flow_name: Optional[str] = None
    phone_number: Optional[str] = None
    phone_number_id: Optional[str] = None
    display_phone_number: Optional[str] = None


class SimulationSendResponse(BaseModel):
    user_message: str
    bot_response: str
    flow_used: Optional[str] = None
    state: Optional[str] = None
    source: str
    detected_intent: Optional[str] = None
    confidence: Optional[float] = None
    requires_handoff: bool = False
    metadata: Dict[str, Any] = Field(default_factory=dict)


import logging
logger = logging.getLogger(__name__)

@router.post("/simulation/send", response_model=SimulationSendResponse)
@router.post("/api/v1/simulation/send", response_model=SimulationSendResponse)
async def simulation_send(
    request: Request,
    payload: SimulationSendPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    conversation_service: ConversationService = Depends(conversation_service_dependency),
) -> SimulationSendResponse:
    logger.info("SIMULATION RECEIVED: %s", payload.model_dump())
    text = payload.message.strip()
    if not text:
        raise HTTPException(status_code=422, detail="message cannot be empty")
    target_tenant_id = resolve_tenant_scope(user, request, payload.tenant_id.strip())

    phone_number = (payload.phone_number or "simulation-user").strip()
    
    metadata = {"source": "admin_simulation"}
    if payload.flow_name:
        metadata["flow"] = payload.flow_name
        
    incoming = NormalizedMessage(
        message_id=f"sim-{uuid4().hex[:12]}",
        tenant_id=target_tenant_id,
        phone_number=phone_number,
        phone_number_id=(payload.phone_number_id or "simulation").strip(),
        display_phone_number=(payload.display_phone_number or phone_number).strip(),
        message_type=MessageType.TEXT,
        direction=MessageDirection.INCOMING,
        content=text,
        raw_content={"source": "admin_simulation"},
        timestamp=datetime.utcnow(),
        metadata=metadata,
    )
    result: ConversationAction = await conversation_service.handle_incoming_message(incoming)

    metadata = dict(result.metadata or {})
    flow_used = _resolve_flow_used(result, metadata)
    state = _resolve_state(result, metadata)

    confidence_raw = metadata.get("confidence")
    confidence: float | None = None
    if confidence_raw is not None:
        try:
            confidence = float(confidence_raw)
        except (TypeError, ValueError):
            confidence = None

    return SimulationSendResponse(
        user_message=text,
        bot_response=result.reply_text,
        flow_used=flow_used,
        state=state,
        source=result.source,
        detected_intent=_resolve_detected_intent(metadata),
        confidence=confidence,
        requires_handoff=result.requires_handoff,
        metadata=metadata,
    )


def _resolve_flow_used(result: ConversationAction, metadata: Dict[str, Any]) -> Optional[str]:
    if isinstance(metadata.get("flow"), str) and metadata.get("flow"):
        return str(metadata.get("flow"))
    for key in ("active_flow", "last_flow"):
        value = result.session_state.get(key)
        if isinstance(value, str) and value:
            return value
    return None


def _resolve_state(result: ConversationAction, metadata: Dict[str, Any]) -> Optional[str]:
    if isinstance(metadata.get("state"), str) and metadata.get("state"):
        return str(metadata.get("state"))
    for key in ("current_state", "last_state"):
        value = result.session_state.get(key)
        if isinstance(value, str) and value:
            return value
    return None


def _resolve_detected_intent(metadata: Dict[str, Any]) -> Optional[str]:
    for key in ("detected_intent", "intent"):
        value = metadata.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None

