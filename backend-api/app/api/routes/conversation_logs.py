"""Observability endpoints for conversation logs."""
from __future__ import annotations

from typing import Any, Dict, List

from fastapi import APIRouter, Depends, Query, Request

from app.api.access import resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.services.conversation_log_service import ConversationLogService
from app.services.dependencies import authenticated_user_dependency, conversation_log_service_dependency

router = APIRouter(prefix="/api/v1/conversation-logs", tags=["Conversation Logs"])


@router.get("")
async def list_conversation_logs(
    request: Request,
    limit: int = Query(default=100, ge=1, le=500),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: ConversationLogService = Depends(conversation_log_service_dependency),
) -> List[Dict[str, Any]]:
    target_tenant_id = resolve_tenant_scope(user, request)
    rows = await service.list_by_tenant(target_tenant_id, limit=limit)
    serialized: List[Dict[str, Any]] = [row.model_dump(mode="json") for row in rows]
    serialized.reverse()
    return serialized

