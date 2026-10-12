"""AI Engine FastAPI application"""
from __future__ import annotations

import logging
import sys
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, Request, Response, status
from fastapi.middleware.cors import CORSMiddleware

from app.api.ai import router as ai_router
from app.api.local_ai import router as local_ai_router
from app.clients.gemini_client import gemini_client
from app.clients.local_ai_client import LocalAIClient
from app.clients.openai_client import openai_client
from app.config.settings import settings
from app.services.ai_service import AIService
from app.services.intent_service import intent_service
from app.services.dependencies import set_ai_service

logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting AI Engine")
    local_client = LocalAIClient(
        base_url=settings.LOCAL_AI_BASE_URL,
        key_id=settings.LOCAL_AI_KEY_ID,
        secret_b64=settings.LOCAL_AI_SECRET_B64,
        connect_timeout_s=settings.LOCAL_AI_CONNECT_TIMEOUT_S,
        total_budget_s=settings.LOCAL_AI_TOTAL_BUDGET_S,
        max_attempts=settings.LOCAL_AI_MAX_ATTEMPTS,
        backoff_base_s=settings.LOCAL_AI_BACKOFF_BASE_S,
        backoff_max_s=settings.LOCAL_AI_BACKOFF_MAX_S,
        breaker_threshold=settings.LOCAL_AI_BREAKER_THRESHOLD,
        breaker_cooldown_s=settings.LOCAL_AI_BREAKER_COOLDOWN_S,
    )
    logger.info(
        "Local AI provider enabled=%s configured=%s", settings.LOCAL_AI_ENABLED, local_client.configured
    )
    app.state.local_ai_client = local_client
    ai_service = AIService(
        openai_client=openai_client,
        gemini_client=gemini_client,
        intent_service=intent_service,
        local_client=local_client,
    )
    set_ai_service(ai_service)
    yield
    await local_client.close()
    logger.info("Shutting down AI Engine")


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="AI engine responsible for natural language generation",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(ai_router)
app.include_router(local_ai_router)


@app.get("/")
async def root() -> dict:
    return {
        "service": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "status": "running",
    }


@app.get("/health")
async def health(request: Request, response: Response) -> dict:
    provider = settings.AI_PROVIDER.strip().lower()
    provider_ready = (
        (provider == "gemini" and bool(settings.GEMINI_API_KEY))
        or (provider == "openai" and bool(settings.OPENAI_API_KEY))
    )
    local_provider_configured = bool(settings.LOCAL_AI_ENABLED and request.app.state.local_ai_client.configured)
    ready = bool(settings.MOCK_AI or provider_ready or local_provider_configured)
    if not ready:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return {
        "status": "healthy" if ready else "unhealthy",
        "service": settings.APP_NAME,
    }


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level=settings.LOG_LEVEL.lower(),
    )

