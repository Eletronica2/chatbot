"""Conversation group admin endpoints."""
from __future__ import annotations

from datetime import datetime
from typing import Any

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel, Field

from app.api.access import assert_tenant_admin, resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.services.conversation_group_service import ConversationGroupService
from app.services.dependencies import (
    authenticated_user_dependency,
    conversation_group_service_dependency,
)

router = APIRouter(prefix="/api/v1/conversation-groups", tags=["Conversation Groups"])


class GroupCreatePayload(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=500)


class GroupUpdatePayload(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=500)


class GroupMembersPayload(BaseModel):
    user_ids: list[str] = Field(default_factory=list)


class GroupResponse(BaseModel):
    id: str
    tenant_id: str
    name: str
    description: str | None = None
    is_default: bool = False
    created_at: datetime | None = None
    updated_at: datetime | None = None


@router.get("", response_model=list[GroupResponse])
async def list_groups(
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: ConversationGroupService = Depends(conversation_group_service_dependency),
) -> list[GroupResponse]:
    tenant_id = resolve_tenant_scope(user, request)
    items = await service.list_groups(tenant_id)
    return [GroupResponse(**item) for item in items]


@router.post("", response_model=GroupResponse, status_code=201)
async def create_group(
    request: Request,
    payload: GroupCreatePayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: ConversationGroupService = Depends(conversation_group_service_dependency),
) -> GroupResponse:
    assert_tenant_admin(user)
    tenant_id = resolve_tenant_scope(user, request)
    item = await service.create_group(
        tenant_id,
        name=payload.name,
        description=payload.description,
    )
    return GroupResponse(**item)


@router.patch("/{group_id}", response_model=GroupResponse)
async def update_group(
    group_id: str,
    request: Request,
    payload: GroupUpdatePayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: ConversationGroupService = Depends(conversation_group_service_dependency),
) -> GroupResponse:
    assert_tenant_admin(user)
    tenant_id = resolve_tenant_scope(user, request)
    item = await service.update_group(
        tenant_id,
        group_id,
        name=payload.name,
        description=payload.description,
    )
    return GroupResponse(**item)


@router.delete("/{group_id}", status_code=204)
async def delete_group(
    group_id: str,
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: ConversationGroupService = Depends(conversation_group_service_dependency),
) -> Response:
    assert_tenant_admin(user)
    tenant_id = resolve_tenant_scope(user, request)
    await service.delete_group(tenant_id, group_id)
    return Response(status_code=204)


@router.post("/{group_id}/members")
async def set_group_members(
    group_id: str,
    request: Request,
    payload: GroupMembersPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: ConversationGroupService = Depends(conversation_group_service_dependency),
) -> list[dict[str, Any]]:
    assert_tenant_admin(user)
    tenant_id = resolve_tenant_scope(user, request)
    return await service.set_members(tenant_id, group_id, payload.user_ids)


@router.get("/{group_id}/members")
async def list_group_members(
    group_id: str,
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: ConversationGroupService = Depends(conversation_group_service_dependency),
) -> list[dict[str, Any]]:
    tenant_id = resolve_tenant_scope(user, request)
    return await service.list_members(tenant_id, group_id)
