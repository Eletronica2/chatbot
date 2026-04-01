"""Message-related API routes."""
from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Request

from app.domain.message import ConversationAction, NormalizedMessage
from app.services.conversation_service import ConversationService
from app.services.dependencies import conversation_service_dependency, internal_api_dependency

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/messages", tags=["Messages"])


@router.post("/incoming", response_model=ConversationAction, dependencies=[Depends(internal_api_dependency)])
async def receive_incoming_message(
    payload: NormalizedMessage,
    request: Request,
    conversation_service: ConversationService = Depends(conversation_service_dependency),
) -> ConversationAction:
    """Entry point for the WhatsApp Gateway."""
    tenant_hint = getattr(request.state, "tenant_id", None)
    if tenant_hint and tenant_hint != payload.tenant_id:
        logger.debug(
            "Tenant override detected header=%s payload=%s",
            tenant_hint,
            payload.tenant_id,
        )
        payload = payload.model_copy(update={"tenant_id": tenant_hint})

    return await conversation_service.handle_incoming_message(payload)

