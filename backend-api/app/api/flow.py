"""Flow execution endpoints"""
from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.domain.message import FlowExecutionResult, NormalizedMessage
from app.services.dependencies import (
    flow_service_dependency,
    session_service_dependency,
)
from app.services.flow_service import FlowService
from app.services.session_service import SessionService


class FlowExecutionPayload(BaseModel):
    """Payload received from clients wanting only a flow resolution"""

    message: NormalizedMessage
    session_state: Dict[str, Any] = Field(default_factory=dict)


class FlowExecutionResponse(BaseModel):
    """Standardized response for flow execution"""

    resolved: bool
    reply_text: Optional[str] = None
    session_state: Dict[str, Any] = Field(default_factory=dict)
    metadata: Dict[str, Any] = Field(default_factory=dict)
    requires_handoff: bool = False


router = APIRouter(prefix="/flow", tags=["Flow"])


@router.post("/execute", response_model=FlowExecutionResponse)
async def execute_flow(
    payload: FlowExecutionPayload,
    flow_service: FlowService = Depends(flow_service_dependency),
    session_service: SessionService = Depends(session_service_dependency),
) -> FlowExecutionResponse:
    """Run the conversational flow without AI fallback"""

    message = payload.message
    session = await session_service.get_or_create_session(
        tenant_id=message.tenant_id,
        phone_number=message.phone_number,
    )

    if payload.session_state:
        session.conversation_state.update(payload.session_state)

    result: FlowExecutionResult = await flow_service.execute_flow(message, session)

    if result.session_state:
        await session_service.update_session(
            session,
            state_updates=result.session_state,
        )

    return FlowExecutionResponse(
        resolved=result.handled,
        reply_text=result.reply_text,
        session_state=session.conversation_state,
        metadata=result.metadata or {},
        requires_handoff=result.requires_handoff,
    )

