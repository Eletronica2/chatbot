"""Admin endpoints to manage local YAML flows."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.api.access import assert_capability, resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.repositories.flow_snapshot_repository import FlowSnapshotRepository
from app.services.admin_audit_service import AdminAuditService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    flow_catalog_service_dependency,
    flow_service_dependency,
    flow_snapshot_repository_dependency,
)
from app.services.flow_catalog_service import FlowCatalogService
from app.services.flow_service import FlowService

router = APIRouter(prefix="/api/v1/flows", tags=["Flow Admin"])


class FlowUpsertPayload(BaseModel):
    yaml_content: str


class FlowSnapshotPayload(BaseModel):
    yaml_content: str | None = None
    overwrite: bool = False


class FlowSnapshotResponse(BaseModel):
    flow_name: str
    yaml_content: str
    source: str = "auto"
    created_at: datetime | None = None
    updated_at: datetime | None = None


@router.get("")
async def list_flows(
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    flow_service: FlowService = Depends(flow_service_dependency),
    snapshots: FlowSnapshotRepository = Depends(flow_snapshot_repository_dependency),
) -> List[Dict[str, Any]]:
    try:
        target_tenant_id = resolve_tenant_scope(user, request)
        items = await flow_service.list_admin_flows(tenant_id=target_tenant_id)
        enriched: List[Dict[str, Any]] = []
        for item in items:
            payload = dict(item) if isinstance(item, dict) else {"name": str(item)}
            flow_name = str(payload.get("name") or "").strip()
            if flow_name:
                snapshot = await snapshots.get(tenant_id=target_tenant_id, flow_name=flow_name)
                payload["has_base_snapshot"] = snapshot is not None
                payload["base_snapshot_at"] = (
                    snapshot.get("updated_at").isoformat() if snapshot and snapshot.get("updated_at") else None
                )
            enriched.append(payload)
        return enriched
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
    snapshots: FlowSnapshotRepository = Depends(flow_snapshot_repository_dependency),
) -> Dict[str, Any]:
    try:
        target_tenant_id = resolve_tenant_scope(user, request)
        payload = await flow_service.get_admin_flow_yaml(flow_name, tenant_id=target_tenant_id)
        snapshot = await snapshots.get(tenant_id=target_tenant_id, flow_name=flow_name)
        result = dict(payload) if isinstance(payload, dict) else {"yaml_content": str(payload)}
        result["has_base_snapshot"] = snapshot is not None
        if snapshot is not None:
            current_yaml = str(result.get("yaml_content") or "")
            base_yaml = str(snapshot.get("yaml_content") or "")
            result["is_base_version"] = current_yaml.strip() == base_yaml.strip()
            result["base_snapshot_at"] = (
                snapshot.get("updated_at").isoformat() if snapshot.get("updated_at") else None
            )
        else:
            result["is_base_version"] = True
            result["base_snapshot_at"] = None
        return result
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
    snapshots: FlowSnapshotRepository = Depends(flow_snapshot_repository_dependency),
) -> Dict[str, Any]:
    try:
        assert_capability(user, "canManageAutomations")
        target_tenant_id = resolve_tenant_scope(user, request)

        # Auto-snapshot of the "base" version BEFORE first user edit.
        existing_snapshot = await snapshots.get(tenant_id=target_tenant_id, flow_name=flow_name)
        if existing_snapshot is None:
            try:
                current_payload = await flow_service.get_admin_flow_yaml(
                    flow_name,
                    tenant_id=target_tenant_id,
                )
                current_yaml = str(current_payload.get("yaml_content") or "")
                if current_yaml.strip():
                    actor_id: int | None = None
                    try:
                        actor_id = int(user.user_id) if user.user_id else None
                    except (TypeError, ValueError):
                        actor_id = None
                    await snapshots.ensure_base(
                        tenant_id=target_tenant_id,
                        flow_name=flow_name,
                        yaml_content=current_yaml,
                        source="auto",
                        created_by_user_id=actor_id,
                    )
            except Exception:
                # snapshot is best-effort; never block the save itself
                pass

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


@router.get("/{flow_name}/base", response_model=FlowSnapshotResponse)
async def get_flow_base_snapshot(
    request: Request,
    flow_name: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    snapshots: FlowSnapshotRepository = Depends(flow_snapshot_repository_dependency),
) -> FlowSnapshotResponse:
    target_tenant_id = resolve_tenant_scope(user, request)
    snapshot = await snapshots.get(tenant_id=target_tenant_id, flow_name=flow_name)
    if snapshot is None:
        raise HTTPException(status_code=404, detail="Snapshot base nao encontrado")
    return FlowSnapshotResponse(
        flow_name=flow_name,
        yaml_content=str(snapshot.get("yaml_content") or ""),
        source=str(snapshot.get("source") or "auto"),
        created_at=snapshot.get("created_at"),
        updated_at=snapshot.get("updated_at"),
    )


@router.post("/{flow_name}/base", response_model=FlowSnapshotResponse)
async def upsert_flow_base_snapshot(
    request: Request,
    flow_name: str,
    payload: FlowSnapshotPayload,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    flow_service: FlowService = Depends(flow_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
    snapshots: FlowSnapshotRepository = Depends(flow_snapshot_repository_dependency),
) -> FlowSnapshotResponse:
    assert_capability(user, "canManageAutomations")
    target_tenant_id = resolve_tenant_scope(user, request)
    yaml_content = (payload.yaml_content or "").strip()
    if not yaml_content:
        try:
            current_payload = await flow_service.get_admin_flow_yaml(
                flow_name,
                tenant_id=target_tenant_id,
            )
        except httpx.HTTPStatusError as exc:
            raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
        yaml_content = str(current_payload.get("yaml_content") or "")
    if not yaml_content.strip():
        raise HTTPException(status_code=400, detail="YAML vazio: nada para snapshotar")

    actor_id: int | None = None
    try:
        actor_id = int(user.user_id) if user.user_id else None
    except (TypeError, ValueError):
        actor_id = None

    saved = await snapshots.upsert(
        tenant_id=target_tenant_id,
        flow_name=flow_name,
        yaml_content=yaml_content,
        source="manual",
        created_by_user_id=actor_id,
        overwrite=True,
    )
    if saved is None:
        raise HTTPException(status_code=500, detail="Falha ao salvar snapshot")

    await audit_service.append(
        tenant_id=target_tenant_id,
        action="flow.base_snapshot",
        entity_type="flow",
        entity_key=flow_name,
        summary=f"Versão base do fluxo {flow_name} atualizada",
        actor=user,
        metadata={"flow_name": flow_name, "source": "manual", "overwrite": payload.overwrite},
    )
    return FlowSnapshotResponse(
        flow_name=flow_name,
        yaml_content=str(saved.get("yaml_content") or ""),
        source=str(saved.get("source") or "manual"),
        created_at=saved.get("created_at"),
        updated_at=saved.get("updated_at"),
    )


@router.post("/{flow_name}/restore")
async def restore_flow_to_base(
    request: Request,
    flow_name: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    flow_service: FlowService = Depends(flow_service_dependency),
    flow_catalog_service: FlowCatalogService = Depends(flow_catalog_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
    snapshots: FlowSnapshotRepository = Depends(flow_snapshot_repository_dependency),
) -> Dict[str, Any]:
    assert_capability(user, "canManageAutomations")
    target_tenant_id = resolve_tenant_scope(user, request)
    snapshot = await snapshots.get(tenant_id=target_tenant_id, flow_name=flow_name)
    if snapshot is None:
        raise HTTPException(status_code=404, detail="Sem versao base para restaurar")
    yaml_content = str(snapshot.get("yaml_content") or "")
    if not yaml_content.strip():
        raise HTTPException(status_code=400, detail="Snapshot base esta vazio")

    try:
        result = await flow_service.upsert_admin_flow_yaml(
            flow_name,
            yaml_content,
            tenant_id=target_tenant_id,
        )
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Flow engine unavailable: {exc}") from exc

    await flow_catalog_service.save_yaml(
        tenant_id=target_tenant_id,
        flow_name=flow_name,
        yaml_content=yaml_content,
    )
    await audit_service.append(
        tenant_id=target_tenant_id,
        action="flow.restore_base",
        entity_type="flow",
        entity_key=flow_name,
        summary=f"Fluxo {flow_name} restaurado para versao base",
        actor=user,
        metadata={"flow_name": flow_name},
    )
    return {
        "flow_name": flow_name,
        "yaml_content": yaml_content,
        "restored_at": datetime.utcnow().isoformat(),
        "result": result,
    }


@router.post("/reload")
async def reload_flows(
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    flow_service: FlowService = Depends(flow_service_dependency),
) -> Dict[str, Any]:
    assert_capability(user, "canManageAutomations")
    try:
        return await flow_service.reload_admin_flows()
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Flow engine unavailable: {exc}") from exc
