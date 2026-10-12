"""Internal endpoints for the local AI server: status probe and knowledge sync proxy.

Only the AI Engine holds the HMAC secret for the local server; the backend reaches these endpoints with
the shared internal API key over the private Docker network.
"""
from __future__ import annotations

import hmac
import time
from typing import Any, Dict, List

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field

from app.clients.local_ai_client import LocalAIError, safe_request_id
from app.config.settings import settings
from app.services.ai_service import AIService
from app.services.dependencies import get_ai_service

router = APIRouter(prefix="/ai/local", tags=["Local AI"])

_status_cache: Dict[str, Any] = {"at": 0.0, "value": None}


def require_internal_key(x_internal_api_key: str | None = Header(None)) -> None:
    expected = settings.INTERNAL_API_KEY or ""
    if not expected:
        raise HTTPException(status_code=503, detail="internal_key_not_configured")
    if not x_internal_api_key or not hmac.compare_digest(x_internal_api_key, expected):
        raise HTTPException(status_code=401, detail="invalid_internal_key")


class SyncPayload(BaseModel):
    tenant_id: str = Field(min_length=2, max_length=64)
    request_id: str | None = Field(None, max_length=120)
    operations: List[Dict[str, Any]] = Field(min_length=1, max_length=20)


def _client_or_503(ai_service: AIService):
    if not ai_service.local_available():
        raise HTTPException(status_code=503, detail="local_ai_disabled")
    return ai_service.local_client


@router.get("/status", dependencies=[Depends(require_internal_key)])
async def local_status(ai_service: AIService = Depends(get_ai_service)) -> Dict[str, Any]:
    base = {
        "enabled": bool(settings.LOCAL_AI_ENABLED),
        "configured": bool(ai_service.local_client and ai_service.local_client.configured),
    }
    if not ai_service.local_available():
        return {**base, "reachable": False, "ready": False}
    now = time.monotonic()
    if _status_cache["value"] is None or now - _status_cache["at"] > settings.LOCAL_AI_STATUS_TTL_S:
        _status_cache["value"] = await ai_service.local_client.probe()
        _status_cache["at"] = now
    probe = dict(_status_cache["value"])
    status = probe.pop("status", None) or {}
    return {
        **base,
        **probe,
        "cached_age_s": round(now - _status_cache["at"], 1),
        "breaker": ai_service.local_client.breaker.snapshot(),
        "queue": status.get("queue"),
        "network": status.get("network"),
    }


@router.post("/knowledge/sync", dependencies=[Depends(require_internal_key)])
async def knowledge_sync(payload: SyncPayload, ai_service: AIService = Depends(get_ai_service)) -> Dict[str, Any]:
    client = _client_or_503(ai_service)
    request_id = safe_request_id(payload.request_id)
    try:
        result, stats = await client.sync(payload.tenant_id, request_id, payload.operations)
    except LocalAIError as exc:
        raise HTTPException(status_code=502 if exc.retryable else 409,
                            detail={"error": exc.code, "retryable": exc.retryable}) from None
    return {**result, "attempts": stats.attempts, "latency_ms": stats.elapsed_ms}


@router.get("/knowledge/manifest", dependencies=[Depends(require_internal_key)])
async def knowledge_manifest(tenant_id: str, ai_service: AIService = Depends(get_ai_service)) -> Dict[str, Any]:
    client = _client_or_503(ai_service)
    try:
        result, _ = await client.manifest(tenant_id, safe_request_id(None))
    except LocalAIError as exc:
        raise HTTPException(status_code=502 if exc.retryable else 409,
                            detail={"error": exc.code, "retryable": exc.retryable}) from None
    return result
