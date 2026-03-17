"""Backend API entrypoint"""
from __future__ import annotations

import logging
import sys
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import conversations, flows_admin, health, messages, tenant_settings
from app.api import flow as flow_routes
from app.config.settings import settings
from app.middlewares.tenant_middleware import TenantMiddleware
from app.repositories.session_repository import InMemorySessionRepository
from app.services.ai_service import AIService
from app.services.conversation_service import ConversationService
from app.services.dependencies import (
    set_conversation_service,
    set_flow_service,
    set_session_service,
    set_tenant_settings_service,
)
from app.services.flow_service import FlowService
from app.services.session_service import SessionService
from app.services.tenant_settings_service import TenantSettingsService

logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Initializing backend services")
    session_repository = InMemorySessionRepository(settings.SESSION_TTL_SECONDS)
    session_service = SessionService(session_repository)
    flow_service = FlowService(settings.FLOW_ENGINE_URL, settings.FLOW_ENGINE_TIMEOUT)
    ai_service = AIService(settings.AI_ENGINE_URL, settings.AI_ENGINE_TIMEOUT)
    tenant_settings_service = TenantSettingsService()
    conversation_service = ConversationService(
        session_service=session_service,
        flow_service=flow_service,
        ai_service=ai_service,
        tenant_settings_service=tenant_settings_service,
    )
    set_conversation_service(conversation_service)
    set_flow_service(flow_service)
    set_session_service(session_service)
    set_tenant_settings_service(tenant_settings_service)

    yield

    logger.info("Backend API shutdown complete")


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="Core Backend API for orchestrating WhatsApp conversations",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(
    TenantMiddleware,
    default_tenant=settings.DEFAULT_TENANT_ID,
)

app.include_router(health.router)
app.include_router(messages.router)
app.include_router(conversations.router)
app.include_router(flows_admin.router)
app.include_router(tenant_settings.router)
app.include_router(flow_routes.router)


@app.get("/")
async def root() -> dict:
    return {
        "service": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "status": "running",
    }


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level=settings.LOG_LEVEL.lower(),
    )
