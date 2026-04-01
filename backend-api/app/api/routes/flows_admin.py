"""Admin endpoints to manage local YAML flows."""
from __future__ import annotations

from typing import Any, Dict, List

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.api.access import resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.services.admin_audit_service import AdminAuditService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    flow_catalog_service_dependency,
    flow_service_dependency,
)
from app.services.flow_catalog_service import FlowCatalogService
from app.services.flow_service import FlowService

router = APIRouter(prefix="/api/v1/flows", tags=["Flow Admin"])


class FlowUpsertPayload(BaseModel):
    yaml_content: str


@router.get("")
async def list_flows(
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    flow_service: FlowService = Depends(flow_service_dependency),
) -> List[Dict[str, Any]]:
    try:
        target_tenant_id = resolve_tenant_scope(user, request)
        return await flow_service.list_admin_flows(tenant_id=target_tenant_id)
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Flow engine unavailable: {exc}") from exc


@router.get("/{flow_name}")
async def get_flow_yaml(
    request: Request,
    flow_name: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    flow_service: FlowService = Depends(flow_service_dependency),
) -> Dict[str, Any]:
    try:
        target_tenant_id = resolve_tenant_scope(user, request)
        return await flow_service.get_admin_flow_yaml(flow_name, tenant_id=target_tenant_id)
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Flow engine unavailable: {exc}") from exc


@router.put("/{flow_name}")
async def upsert_flow_yaml(
    request: Request,
    flow_name: str,
    payload: FlowUpsertPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    flow_service: FlowService = Depends(flow_service_dependency),
    flow_catalog_service: FlowCatalogService = Depends(flow_catalog_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> Dict[str, Any]:
    try:
        target_tenant_id = resolve_tenant_scope(user, request)
        result = await flow_service.upsert_admin_flow_yaml(
            flow_name,
            payload.yaml_content,
            tenant_id=target_tenant_id,
        )
        await flow_catalog_service.save_yaml(
            tenant_id=target_tenant_id,
            flow_name=flow_name,
            yaml_content=payload.yaml_content,
        )
        await audit_service.append(
            tenant_id=target_tenant_id,
            action="flow.update",
            entity_type="flow",
            entity_key=flow_name,
            summary=f"Fluxo {flow_name} salvo",
            actor=user,
            metadata={"flow_name": flow_name},
        )
        return result
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Flow engine unavailable: {exc}") from exc


@router.post("/reload")
async def reload_flows(
    _: AuthenticatedUser = Depends(authenticated_user_dependency),
    flow_service: FlowService = Depends(flow_service_dependency),
) -> Dict[str, Any]:
    try:
        return await flow_service.reload_admin_flows()
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Flow engine unavailable: {exc}") from exc

