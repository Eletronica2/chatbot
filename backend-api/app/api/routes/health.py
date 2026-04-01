"""Health and diagnostics endpoints"""
from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter

from app.config.settings import settings

router = APIRouter(tags=["Health"])


@router.get("/health")
async def health_check() -> dict:
    """Simple liveness probe"""
    return {
        "status": "healthy",
        "service": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "timestamp": datetime.utcnow().isoformat(),
    }

