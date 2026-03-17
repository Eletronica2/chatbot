"""Admin endpoints to manage local YAML flows"""
from __future__ import annotations

from typing import Any, Dict, List

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.services.dependencies import flow_service_dependency
from app.services.flow_service import FlowService

router = APIRouter(prefix="/api/v1/flows", tags=["Flow Admin"])


class FlowUpsertPayload(BaseModel):
    yaml_content: str


@router.get("")
async def list_flows(
    flow_service: FlowService = Depends(flow_service_dependency),
) -> List[Dict[str, Any]]:
    try:
        return await flow_service.list_admin_flows()
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Flow engine unavailable: {exc}") from exc


@router.get("/{flow_name}")
async def get_flow_yaml(
    flow_name: str,
    flow_service: FlowService = Depends(flow_service_dependency),
) -> Dict[str, Any]:
    try:
        return await flow_service.get_admin_flow_yaml(flow_name)
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Flow engine unavailable: {exc}") from exc


@router.put("/{flow_name}")
async def upsert_flow_yaml(
    flow_name: str,
    payload: FlowUpsertPayload,
    flow_service: FlowService = Depends(flow_service_dependency),
) -> Dict[str, Any]:
    try:
        return await flow_service.upsert_admin_flow_yaml(flow_name, payload.yaml_content)
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Flow engine unavailable: {exc}") from exc


@router.post("/reload")
async def reload_flows(
    flow_service: FlowService = Depends(flow_service_dependency),
) -> Dict[str, Any]:
    try:
        return await flow_service.reload_admin_flows()
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Flow engine unavailable: {exc}") from exc
