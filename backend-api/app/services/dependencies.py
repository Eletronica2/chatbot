"""Service container helpers"""
from __future__ import annotations

from typing import Optional

from fastapi import Depends

from app.services.conversation_service import ConversationService
from app.services.flow_service import FlowService
from app.services.session_service import SessionService
from app.services.tenant_settings_service import TenantSettingsService

_conversation_service: Optional[ConversationService] = None
_flow_service: Optional[FlowService] = None
_session_service: Optional[SessionService] = None
_tenant_settings_service: Optional[TenantSettingsService] = None


def set_conversation_service(service: ConversationService) -> None:
    global _conversation_service
    _conversation_service = service


def get_conversation_service() -> ConversationService:
    if _conversation_service is None:  # pragma: no cover - configuration guard
        raise RuntimeError("ConversationService not configured")
    return _conversation_service


def conversation_service_dependency(
    service: ConversationService = Depends(get_conversation_service),
) -> ConversationService:
    """Wrapper to expose the conversation service as a FastAPI dependency"""
    return service


def set_flow_service(service: FlowService) -> None:
    global _flow_service
    _flow_service = service


def get_flow_service() -> FlowService:
    if _flow_service is None:  # pragma: no cover - guard clause
        raise RuntimeError("FlowService not configured")
    return _flow_service


def flow_service_dependency(
    service: FlowService = Depends(get_flow_service),
) -> FlowService:
    return service


def set_session_service(service: SessionService) -> None:
    global _session_service
    _session_service = service


def get_session_service() -> SessionService:
    if _session_service is None:  # pragma: no cover
        raise RuntimeError("SessionService not configured")
    return _session_service


def session_service_dependency(
    service: SessionService = Depends(get_session_service),
) -> SessionService:
    return service


def set_tenant_settings_service(service: TenantSettingsService) -> None:
    global _tenant_settings_service
    _tenant_settings_service = service


def get_tenant_settings_service() -> TenantSettingsService:
    if _tenant_settings_service is None:  # pragma: no cover
        raise RuntimeError("TenantSettingsService not configured")
    return _tenant_settings_service


def tenant_settings_service_dependency(
    service: TenantSettingsService = Depends(get_tenant_settings_service),
) -> TenantSettingsService:
    return service
