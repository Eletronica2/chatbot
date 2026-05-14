"""Service container helpers."""
from __future__ import annotations

from typing import Optional

from fastapi import Depends, Request

from app.domain.auth import AuthenticatedUser
from app.services.auth_service import AuthService
from app.services.billing_service import BillingService
from app.services.conversation_service import ConversationService
from app.services.flow_catalog_service import FlowCatalogService
from app.services.flow_service import FlowService
from app.services.message_service import MessageService
from app.services.session_service import SessionService
from app.services.subscription_service import SubscriptionService
from app.services.tenant_admin_service import TenantAdminService
from app.services.tenant_settings_service import TenantSettingsService
from app.services.conversation_log_service import ConversationLogService
from app.services.whatsapp_account_service import WhatsAppAccountService
from app.services.admin_audit_service import AdminAuditService
from app.services.dashboard_service import DashboardService
from app.services.email_service import EmailService
from app.services.tenant_user_service import TenantUserService
from app.services.flow_actions_service import FlowActionsService

_conversation_service: Optional[ConversationService] = None
_flow_service: Optional[FlowService] = None
_session_service: Optional[SessionService] = None
_tenant_settings_service: Optional[TenantSettingsService] = None
_subscription_service: Optional[SubscriptionService] = None
_actions_service: Optional[FlowActionsService] = None
_conversation_log_service: Optional[ConversationLogService] = None
_message_service: Optional[MessageService] = None
_auth_service: Optional[AuthService] = None
_whatsapp_account_service: Optional[WhatsAppAccountService] = None
_flow_catalog_service: Optional[FlowCatalogService] = None
_tenant_admin_service: Optional[TenantAdminService] = None
_admin_audit_service: Optional[AdminAuditService] = None
_tenant_user_service: Optional[TenantUserService] = None
_email_service: Optional[EmailService] = None
_billing_service: Optional[BillingService] = None
_dashboard_service: Optional[DashboardService] = None


def set_conversation_service(service: ConversationService) -> None:
    global _conversation_service
    _conversation_service = service


def get_conversation_service() -> ConversationService:
    if _conversation_service is None:
        raise RuntimeError("ConversationService not configured")
    return _conversation_service


def conversation_service_dependency(
    service: ConversationService = Depends(get_conversation_service),
) -> ConversationService:
    return service


def set_flow_service(service: FlowService) -> None:
    global _flow_service
    _flow_service = service


def get_flow_service() -> FlowService:
    if _flow_service is None:
        raise RuntimeError("FlowService not configured")
    return _flow_service


def flow_service_dependency(service: FlowService = Depends(get_flow_service)) -> FlowService:
    return service


def set_session_service(service: SessionService) -> None:
    global _session_service
    _session_service = service


def get_session_service() -> SessionService:
    if _session_service is None:
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
    if _tenant_settings_service is None:
        raise RuntimeError("TenantSettingsService not configured")
    return _tenant_settings_service


def tenant_settings_service_dependency(
    service: TenantSettingsService = Depends(get_tenant_settings_service),
) -> TenantSettingsService:
    return service


def set_subscription_service(service: SubscriptionService) -> None:
    global _subscription_service
    _subscription_service = service


def get_subscription_service() -> SubscriptionService:
    if _subscription_service is None:
        raise RuntimeError("SubscriptionService not configured")
    return _subscription_service


def subscription_service_dependency(
    service: SubscriptionService = Depends(get_subscription_service),
) -> SubscriptionService:
    return service


def set_conversation_log_service(service: ConversationLogService) -> None:
    global _conversation_log_service
    _conversation_log_service = service


def get_conversation_log_service() -> ConversationLogService:
    if _conversation_log_service is None:
        raise RuntimeError("ConversationLogService not configured")
    return _conversation_log_service


def conversation_log_service_dependency(
    service: ConversationLogService = Depends(get_conversation_log_service),
) -> ConversationLogService:
    return service


def set_message_service(service: MessageService) -> None:
    global _message_service
    _message_service = service


def get_message_service() -> MessageService:
    if _message_service is None:
        raise RuntimeError("MessageService not configured")
    return _message_service


def message_service_dependency(
    service: MessageService = Depends(get_message_service),
) -> MessageService:
    return service


def set_auth_service(service: AuthService) -> None:
    global _auth_service
    _auth_service = service


def get_auth_service() -> AuthService:
    if _auth_service is None:
        raise RuntimeError("AuthService not configured")
    return _auth_service


def auth_service_dependency(service: AuthService = Depends(get_auth_service)) -> AuthService:
    return service


def authenticated_user_dependency(
    request: Request,
    service: AuthService = Depends(get_auth_service),
) -> AuthenticatedUser:
    return service.authenticate_request(request, required=True)


def optional_authenticated_user_dependency(
    request: Request,
    service: AuthService = Depends(get_auth_service),
) -> AuthenticatedUser | None:
    return service.authenticate_request(request, required=False)


def internal_api_dependency(
    request: Request,
    service: AuthService = Depends(get_auth_service),
) -> None:
    service.assert_internal_api_key(request)


def set_whatsapp_account_service(service: WhatsAppAccountService) -> None:
    global _whatsapp_account_service
    _whatsapp_account_service = service


def get_whatsapp_account_service() -> WhatsAppAccountService:
    if _whatsapp_account_service is None:
        raise RuntimeError("WhatsAppAccountService not configured")
    return _whatsapp_account_service


def whatsapp_account_service_dependency(
    service: WhatsAppAccountService = Depends(get_whatsapp_account_service),
) -> WhatsAppAccountService:
    return service


def set_flow_catalog_service(service: FlowCatalogService) -> None:
    global _flow_catalog_service
    _flow_catalog_service = service


def get_flow_catalog_service() -> FlowCatalogService:
    if _flow_catalog_service is None:
        raise RuntimeError("FlowCatalogService not configured")
    return _flow_catalog_service


def flow_catalog_service_dependency(
    service: FlowCatalogService = Depends(get_flow_catalog_service),
) -> FlowCatalogService:
    return service


def set_tenant_admin_service(service: TenantAdminService) -> None:
    global _tenant_admin_service
    _tenant_admin_service = service


def get_tenant_admin_service() -> TenantAdminService:
    if _tenant_admin_service is None:
        raise RuntimeError("TenantAdminService not configured")
    return _tenant_admin_service


def tenant_admin_service_dependency(
    service: TenantAdminService = Depends(get_tenant_admin_service),
) -> TenantAdminService:
    return service


def set_admin_audit_service(service: AdminAuditService) -> None:
    global _admin_audit_service
    _admin_audit_service = service


def get_admin_audit_service() -> AdminAuditService:
    if _admin_audit_service is None:
        raise RuntimeError("AdminAuditService not configured")
    return _admin_audit_service


def admin_audit_service_dependency(
    service: AdminAuditService = Depends(get_admin_audit_service),
) -> AdminAuditService:
    return service


def set_tenant_user_service(service: TenantUserService) -> None:
    global _tenant_user_service
    _tenant_user_service = service


def get_tenant_user_service() -> TenantUserService:
    if _tenant_user_service is None:
        raise RuntimeError("TenantUserService not configured")
    return _tenant_user_service


def tenant_user_service_dependency(
    service: TenantUserService = Depends(get_tenant_user_service),
) -> TenantUserService:
    return service


def set_email_service(service: EmailService) -> None:
    global _email_service
    _email_service = service


def get_email_service() -> EmailService:
    if _email_service is None:
        raise RuntimeError("EmailService not configured")
    return _email_service


def email_service_dependency(
    service: EmailService = Depends(get_email_service),
) -> EmailService:
    return service


def set_billing_service(service: BillingService) -> None:
    global _billing_service
    _billing_service = service


def get_billing_service() -> BillingService:
    if _billing_service is None:
        raise RuntimeError("BillingService not configured")
    return _billing_service


def billing_service_dependency(
    service: BillingService = Depends(get_billing_service),
) -> BillingService:
    return service


def set_dashboard_service(service: DashboardService) -> None:
    global _dashboard_service
    _dashboard_service = service


def get_dashboard_service() -> DashboardService:
    if _dashboard_service is None:
        raise RuntimeError("DashboardService not configured")
    return _dashboard_service


def dashboard_service_dependency(
    service: DashboardService = Depends(get_dashboard_service),
) -> DashboardService:
    return service


def set_actions_service(service: FlowActionsService) -> None:
    global _actions_service
    _actions_service = service


def get_actions_service() -> FlowActionsService:
    if _actions_service is None:
        raise RuntimeError("FlowActionsService not configured")
    return _actions_service


def actions_service_dependency(
    service: FlowActionsService = Depends(get_actions_service),
) -> FlowActionsService:
    return service

