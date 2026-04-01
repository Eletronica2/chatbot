"""API routes for Flow Engine"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel

from app.config.settings import settings
from app.domain.flow import FlowExecutePayload, FlowExecutionRequest, FlowExecutionResponse
from app.services.flow_service import FlowService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/flow")
legacy_router = APIRouter()

flow_service_instance: FlowService | None = None


class FlowSummary(BaseModel):
    name: str
    description: str | None = None
    start_state: str | None = None


class FlowYamlResponse(BaseModel):
    name: str
    yaml_content: str


class FlowUpsertPayload(BaseModel):
    yaml_content: str


class FlowUpsertResponse(BaseModel):
    ok: bool
    name: str


class FlowReloadResponse(BaseModel):
    ok: bool
    loaded_flows: int


def set_flow_service(service: FlowService) -> None:
    global flow_service_instance
    flow_service_instance = service


def get_flow_service() -> FlowService:
    if flow_service_instance is None:  # pragma: no cover - guard clause
        raise RuntimeError("Flow service not initialized")
    return flow_service_instance


@router.post("/execute", response_model=FlowExecutionResponse)
async def execute_flow(
    payload: FlowExecutePayload,
    flow_service: FlowService = Depends(get_flow_service),
) -> FlowExecutionResponse:
    """Entry point consumed by backend-api"""
    logger.info(
        "Executing flow for tenant %s session %s",
        payload.tenant_id,
        payload.session_id,
    )
    flow_request = FlowExecutionRequest.from_execute_payload(payload)
    return await flow_service.execute_flow(flow_request)


@legacy_router.post("/flows/execute", response_model=FlowExecutionResponse)
async def legacy_execute_flow(
    payload: FlowExecutionRequest,
    flow_service: FlowService = Depends(get_flow_service),
) -> FlowExecutionResponse:
    logger.info(
        "Executing legacy flow endpoint tenant=%s phone=%s",
        payload.tenant_id,
        payload.phone_number,
    )
    return await flow_service.execute_flow(payload)


@router.get("/admin/flows", response_model=List[FlowSummary])
async def list_flows(
    tenant_id: str | None = Query(default=None),
    flow_service: FlowService = Depends(get_flow_service),
) -> List[FlowSummary]:
    loader = flow_service.loader
    loader.load_flows()
    rows: List[FlowSummary] = []
    for name in loader.list_flow_names(tenant_id):
        flow = loader.get_flow(name, tenant_id)
        rows.append(
            FlowSummary(
                name=name,
                description=flow.description if flow else None,
                start_state=flow.start_state if flow else None,
            )
        )
    return rows


@router.get("/admin/flows/{flow_name}", response_model=FlowYamlResponse)
async def get_flow_yaml(
    flow_name: str,
    tenant_id: str | None = Query(default=None),
    flow_service: FlowService = Depends(get_flow_service),
) -> FlowYamlResponse:
    try:
        yaml_content = flow_service.loader.get_flow_yaml(flow_name, tenant_id)
    except Exception as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return FlowYamlResponse(name=flow_name, yaml_content=yaml_content)


@router.put("/admin/flows/{flow_name}", response_model=FlowUpsertResponse)
async def upsert_flow_yaml(
    flow_name: str,
    payload: FlowUpsertPayload,
    tenant_id: str | None = Query(default=None),
    flow_service: FlowService = Depends(get_flow_service),
) -> FlowUpsertResponse:
    try:
        flow_service.loader.upsert_flow_yaml(flow_name, payload.yaml_content, tenant_id)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return FlowUpsertResponse(ok=True, name=flow_name)


@router.post("/admin/reload", response_model=FlowReloadResponse)
async def reload_flows(
    flow_service: FlowService = Depends(get_flow_service),
) -> FlowReloadResponse:
    flows = flow_service.loader.load_flows()
    return FlowReloadResponse(ok=True, loaded_flows=len(flows))


@router.get("/health")
async def health_check() -> dict:
    return {
        "status": "healthy",
        "service": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "timestamp": datetime.utcnow().isoformat(),
    }
