"""Flow Actions API routes."""
from __future__ import annotations

import base64
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field

from app.api.access import assert_capability, resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.services.dependencies import (
    actions_service_dependency,
    authenticated_user_dependency,
)
from app.services.flow_actions_service import FlowActionsService

router = APIRouter(prefix="/api/v1/actions", tags=["Flow Actions"])


# ── Pydantic schemas ──────────────────────────────────────────────────────────

class ActionCreatePayload(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    action_type: str
    config: Dict[str, Any] = Field(default_factory=dict)


class ActionUpdatePayload(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=120)
    config: Optional[Dict[str, Any]] = None


class ActionResponse(BaseModel):
    id: int
    tenant_id: int
    name: str
    action_type: str
    config: Dict[str, Any]
    created_at: str
    updated_at: str


# ── Routes ────────────────────────────────────────────────────────────────────

@router.get("", response_model=List[ActionResponse])
async def list_actions(
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: FlowActionsService = Depends(actions_service_dependency),
) -> List[ActionResponse]:
    tenant_key = resolve_tenant_scope(user, request)
    rows = service.list_actions(tenant_key)
    return [ActionResponse(**r) for r in rows]


@router.get("/{action_id}", response_model=ActionResponse)
async def get_action(
    action_id: int,
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: FlowActionsService = Depends(actions_service_dependency),
) -> ActionResponse:
    tenant_key = resolve_tenant_scope(user, request)
    row = service.get_action(action_id, tenant_key)
    if not row:
        raise HTTPException(status_code=404, detail="Action not found")
    return ActionResponse(**row)


@router.post("", response_model=ActionResponse, status_code=201)
async def create_action(
    payload: ActionCreatePayload,
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: FlowActionsService = Depends(actions_service_dependency),
) -> ActionResponse:
    assert_capability(user, "canManageActions")
    tenant_key = resolve_tenant_scope(user, request)
    try:
        row = service.create_action(
            tenant_key=tenant_key,
            name=payload.name,
            action_type=payload.action_type,
            config=payload.config,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return ActionResponse(**row)


@router.patch("/{action_id}", response_model=ActionResponse)
async def update_action(
    action_id: int,
    payload: ActionUpdatePayload,
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: FlowActionsService = Depends(actions_service_dependency),
) -> ActionResponse:
    assert_capability(user, "canManageActions")
    tenant_key = resolve_tenant_scope(user, request)
    row = service.update_action(
        action_id=action_id,
        tenant_key=tenant_key,
        name=payload.name,
        config=payload.config,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Action not found")
    return ActionResponse(**row)


@router.delete("/{action_id}", status_code=204)
async def delete_action(
    action_id: int,
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: FlowActionsService = Depends(actions_service_dependency),
) -> Response:
    assert_capability(user, "canManageActions")
    tenant_key = resolve_tenant_scope(user, request)
    deleted = service.delete_action(action_id, tenant_key)
    if not deleted:
        raise HTTPException(status_code=404, detail="Action not found")
    return Response(status_code=204)


@router.get("/{action_id}/media")
async def get_action_media(
    action_id: int,
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: FlowActionsService = Depends(actions_service_dependency),
) -> Response:
    """Return the raw image bytes for a send_image action (used by the bot)."""
    tenant_key = resolve_tenant_scope(user, request)
    row = service.get_action(action_id, tenant_key)
    if not row:
        raise HTTPException(status_code=404, detail="Action not found")
    if row["action_type"] != "send_image":
        raise HTTPException(status_code=400, detail="Not an image action")
    config = row["config"]
    image_data = config.get("image_data", "")
    mime_type = config.get("mime_type", "image/jpeg")
    if not image_data:
        raise HTTPException(status_code=404, detail="No image stored")
    raw_bytes = base64.b64decode(image_data)
    return Response(content=raw_bytes, media_type=mime_type)
