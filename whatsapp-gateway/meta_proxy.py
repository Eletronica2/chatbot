"""Proxy Meta platform callbacks to backend-api (single public tunnel on gateway port)."""
import logging

import httpx
from fastapi import APIRouter, Request
from fastapi.responses import Response

from config import settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/meta", tags=["Meta Proxy"])


@router.api_route("/{path:path}", methods=["GET", "POST", "HEAD", "OPTIONS"])
async def proxy_meta_callbacks(request: Request, path: str) -> Response:
    target = f"{settings.BACKEND_API_URL.rstrip('/')}/api/v1/meta/{path}"
    if request.url.query:
        target = f"{target}?{request.url.query}"

    headers = {
        key: value
        for key, value in request.headers.items()
        if key.lower() not in ("host", "content-length", "transfer-encoding")
    }

    body = await request.body()
    try:
        async with httpx.AsyncClient(timeout=settings.BACKEND_API_TIMEOUT) as client:
            upstream = await client.request(
                request.method,
                target,
                headers=headers,
                content=body if body else None,
            )
    except httpx.RequestError as exc:
        logger.error("Meta proxy failed for %s: %s", target, exc)
        return Response(content='{"detail":"backend unavailable"}', status_code=502, media_type="application/json")

    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        headers={
            key: value
            for key, value in upstream.headers.items()
            if key.lower() not in ("transfer-encoding", "content-encoding", "content-length")
        },
        media_type=upstream.headers.get("content-type"),
    )
