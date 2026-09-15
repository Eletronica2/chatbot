"""Quick reply endpoints — current user's replies only."""
from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel, Field

from app.api.access import resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.services.dependencies import (
    authenticated_user_dependency,
    quick_reply_service_dependency,
)
from app.services.quick_reply_service import QuickReplyService

router = APIRouter(prefix="/api/v1/quick-replies", tags=["Quick Replies"])


class QuickReplyCreatePayload(BaseModel):
    title: str = Field(..., min_length=1, max_length=160)
    shortcut: str = Field(..., min_length=1, max_length=64)
    content: str = Field(..., min_length=1)


class QuickReplyUpdatePayload(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=160)
    shortcut: str | None = Field(default=None, min_length=1, max_length=64)
    content: str | None = Field(default=None, min_length=1)


class QuickReplyResponse(BaseModel):
    id: str
    tenant_id: str
    user_id: str
    title: str
    shortcut: str
    content: str
    created_at: datetime | None = None
    updated_at: datetime | None = None


@router.get("", response_model=list[QuickReplyResponse])
async def list_quick_replies(
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: QuickReplyService = Depends(quick_reply_service_dependency),
) -> list[QuickReplyResponse]:
    tenant_id = resolve_tenant_scope(user, request)
    items = await service.list_for_user(tenant_id, user.user_id)
    return [QuickReplyResponse(**item) for item in items]


@router.post("", response_model=QuickReplyResponse, status_code=201)
async def create_quick_reply(
    request: Request,
    payload: QuickReplyCreatePayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: QuickReplyService = Depends(quick_reply_service_dependency),
) -> QuickReplyResponse:
    tenant_id = resolve_tenant_scope(user, request)
    item = await service.create(
        tenant_id,
        user.user_id,
        title=payload.title,
        shortcut=payload.shortcut,
        content=payload.content,
    )
    return QuickReplyResponse(**item)


@router.patch("/{reply_id}", response_model=QuickReplyResponse)
async def update_quick_reply(
    reply_id: str,
    request: Request,
    payload: QuickReplyUpdatePayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: QuickReplyService = Depends(quick_reply_service_dependency),
) -> QuickReplyResponse:
    tenant_id = resolve_tenant_scope(user, request)
    item = await service.update(
        tenant_id,
        user.user_id,
        reply_id,
        title=payload.title,
        shortcut=payload.shortcut,
        content=payload.content,
    )
    return QuickReplyResponse(**item)


@router.delete("/{reply_id}", status_code=204)
async def delete_quick_reply(
    reply_id: str,
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: QuickReplyService = Depends(quick_reply_service_dependency),
) -> Response:
    tenant_id = resolve_tenant_scope(user, request)
    await service.delete(tenant_id, user.user_id, reply_id)
    return Response(status_code=204)
