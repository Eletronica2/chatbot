"""Backend API entrypoint."""
from __future__ import annotations

import logging
import sys
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api import flow as flow_routes
from app.api.routes import (
    actions,
    admin_audit_logs,
    admin_tenants,
    admin_users,
    auth,
    billing,
    billing_webhooks,
    conversation_groups,
    conversation_logs,
    conversations,
    dashboard,
    fiscal,
    flows_admin,
    health,
    internal_whatsapp,
    leads,
    messages,
    proposals,
    quick_replies,
    simulation,
    subscriptions,
    tenant_settings,
    usage,
    whatsapp_accounts,
    whatsapp_templates,
    whatsapp_onboarding,
    meta_callbacks,
)
from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.middlewares.tenant_middleware import TenantMiddleware
from app.repositories.flow_catalog_repository import FlowCatalogRepository
from app.repositories.flow_snapshot_repository import FlowSnapshotRepository
from app.repositories.lead_repository import LeadRepository
from app.repositories.proposal_repository import ProposalRepository
from app.repositories.message_repository import MySQLMessageRepository
from app.repositories.session_repository import MySQLSessionRepository
from app.repositories.user_repository import UserRepository
from app.repositories.whatsapp_account_repository import WhatsAppAccountRepository
from app.security.crypto import TokenCipher
from app.services.ai_service import AIService
from app.services.auth_service import AuthService
from app.services.billing_service import BillingService
from app.services.conversation_log_service import ConversationLogService
from app.services.conversation_service import ConversationService
from app.services.dependencies import (
    set_admin_audit_service,
    set_auth_service,
    set_billing_service,
    set_conversation_group_service,
    set_conversation_log_service,
    set_conversation_service,
    set_dashboard_service,
    set_email_service,
    set_fiscal_provider,
    set_flow_catalog_service,
    set_flow_service,
    set_flow_snapshot_repository,
    set_lead_service,
    set_message_service,
    set_proposal_service,
    set_quick_reply_service,
    set_session_service,
    set_subscription_service,
    set_tenant_admin_service,
    set_tenant_settings_service,
    set_tenant_user_service,
    set_actions_service,
    set_usage_ledger_service,
    set_whatsapp_account_service,
    set_whatsapp_onboarding_service,
    set_whatsapp_template_service,
    set_meta_graph_service,
)
from app.services.admin_audit_service import AdminAuditService
from app.services.tenant_admin_service import TenantAdminService
from app.services.dashboard_service import DashboardService
from app.services.email_service import EmailService
from app.services.flow_catalog_service import FlowCatalogService
from app.services.flow_service import FlowService
from app.services.lead_service import LeadService
from app.services.message_service import MessageService
from app.services.proposal_service import ProposalService
from app.services.session_service import SessionService
from app.services.subscription_service import SubscriptionService
from app.services.tenant_settings_service import TenantSettingsService
from app.services.tenant_user_service import TenantUserService
from app.services.flow_actions_service import FlowActionsService
from app.services.whatsapp_account_service import WhatsAppAccountService
from app.services.whatsapp_onboarding_service import WhatsAppOnboardingService
from app.services.whatsapp_template_service import WhatsAppTemplateService
from app.services.meta_graph_service import MetaGraphService
from app.services.conversation_group_service import ConversationGroupService
from app.services.quick_reply_service import QuickReplyService
from app.services.usage_ledger_service import UsageLedgerService
from app.services.fiscal_provider import build_fiscal_provider

logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Initializing backend services")
    database = MySQLDatabase(settings.DATABASE_URL)
    database.bootstrap(
        default_tenant_key=settings.DEFAULT_TENANT_ID,
        default_tenant_name=settings.DEFAULT_TENANT_NAME,
        default_tenant_email=settings.DEFAULT_TENANT_EMAIL,
    )

    session_repository = MySQLSessionRepository(database)
    message_repository = MySQLMessageRepository(database)
    user_repository = UserRepository(database)
    whatsapp_account_repository = WhatsAppAccountRepository(database)
    flow_catalog_repository = FlowCatalogRepository(database)
    flow_snapshot_repository = FlowSnapshotRepository(database)
    lead_repository = LeadRepository(database)
    proposal_repository = ProposalRepository(database)

    session_service = SessionService(session_repository)
    flow_service = FlowService(settings.FLOW_ENGINE_URL, settings.FLOW_ENGINE_TIMEOUT)
    ai_service = AIService(settings.AI_ENGINE_URL, settings.AI_ENGINE_TIMEOUT)
    message_service = MessageService(message_repository)
    tenant_settings_service = TenantSettingsService(database)
    subscription_service = SubscriptionService(database, message_repository, settings)
    conversation_log_service = ConversationLogService(database)
    admin_audit_service = AdminAuditService(database)
    auth_service = AuthService(user_repository, settings)
    await auth_service.ensure_default_user()
    email_service = EmailService(settings, database)
    billing_service = BillingService(
        database=database,
        settings=settings,
        email_service=email_service,
    )
    meta_graph_service = MetaGraphService()
    whatsapp_account_service = WhatsAppAccountService(
        whatsapp_account_repository,
        TokenCipher(settings.APP_SECRET_KEY),
        meta_graph_service,
    )
    whatsapp_template_service = WhatsAppTemplateService(
        meta_graph_service,
        whatsapp_account_service,
    )
    whatsapp_onboarding_service = WhatsAppOnboardingService(
        meta_graph_service,
        whatsapp_account_service,
    )
    flow_catalog_service = FlowCatalogService(flow_catalog_repository)
    tenant_user_service = TenantUserService(
        database=database,
        user_repository=user_repository,
        settings=settings,
    )
    tenant_admin_service = TenantAdminService(
        database=database,
        tenant_settings_service=tenant_settings_service,
        subscription_service=subscription_service,
        settings=settings,
        flow_service=flow_service,
        flow_catalog_service=flow_catalog_service,
    )
    dashboard_service = DashboardService(
        database=database,
        subscription_service=subscription_service,
        billing_service=billing_service,
        settings=settings,
        flow_service=flow_service,
    )
    conversation_service = ConversationService(
        session_service=session_service,
        flow_service=flow_service,
        ai_service=ai_service,
        tenant_settings_service=tenant_settings_service,
        subscription_service=subscription_service,
        conversation_log_service=conversation_log_service,
        message_service=message_service,
    )

    set_conversation_service(conversation_service)
    set_flow_service(flow_service)
    set_session_service(session_service)
    set_tenant_settings_service(tenant_settings_service)
    set_subscription_service(subscription_service)
    set_conversation_log_service(conversation_log_service)
    set_admin_audit_service(admin_audit_service)
    set_message_service(message_service)
    set_auth_service(auth_service)
    set_email_service(email_service)
    set_billing_service(billing_service)
    set_dashboard_service(dashboard_service)
    set_whatsapp_account_service(whatsapp_account_service)
    set_meta_graph_service(meta_graph_service)
    set_whatsapp_template_service(whatsapp_template_service)
    set_whatsapp_onboarding_service(whatsapp_onboarding_service)
    set_flow_catalog_service(flow_catalog_service)
    set_tenant_admin_service(tenant_admin_service)
    set_tenant_user_service(tenant_user_service)

    actions_service = FlowActionsService(database)
    set_actions_service(actions_service)

    lead_service = LeadService(
        repository=lead_repository,
        email_service=email_service,
        settings=settings,
    )
    set_lead_service(lead_service)
    set_flow_snapshot_repository(flow_snapshot_repository)

    proposal_service = ProposalService(
        repository=proposal_repository,
        lead_service=lead_service,
        tenant_admin_service=tenant_admin_service,
        tenant_user_service=tenant_user_service,
    )
    set_proposal_service(proposal_service)

    conversation_group_service = ConversationGroupService(database)
    set_conversation_group_service(conversation_group_service)
    quick_reply_service = QuickReplyService(database)
    set_quick_reply_service(quick_reply_service)
    usage_ledger_service = UsageLedgerService(database)
    set_usage_ledger_service(usage_ledger_service)
    set_fiscal_provider(
        build_fiscal_provider(
            provider=settings.FISCAL_PROVIDER,
            ready=bool(settings.FISCAL_PROVIDER_READY),
        )
    )

    await _sync_default_flows(flow_service, flow_catalog_service)
    await tenant_admin_service.ensure_bootstrap_tenant(
        tenant_id=settings.BOOTSTRAP_COMPANY_TENANT_ID,
        name=settings.BOOTSTRAP_COMPANY_NAME,
        email=settings.BOOTSTRAP_COMPANY_EMAIL,
        owner_name=settings.BOOTSTRAP_COMPANY_ADMIN_NAME,
        owner_email=settings.BOOTSTRAP_COMPANY_ADMIN_EMAIL,
        owner_password=settings.BOOTSTRAP_COMPANY_ADMIN_PASSWORD,
        plan=settings.BOOTSTRAP_COMPANY_PLAN,
        monthly_message_limit=settings.BOOTSTRAP_COMPANY_MONTHLY_MESSAGE_LIMIT,
    )
    await tenant_admin_service.ensure_bootstrap_tenant(
        tenant_id=settings.BOOTSTRAP_PIZZARIA_TENANT_ID,
        name=settings.BOOTSTRAP_PIZZARIA_NAME,
        email=settings.BOOTSTRAP_PIZZARIA_EMAIL,
        owner_name=settings.BOOTSTRAP_PIZZARIA_ADMIN_NAME,
        owner_email=settings.BOOTSTRAP_PIZZARIA_ADMIN_EMAIL,
        owner_password=settings.BOOTSTRAP_PIZZARIA_ADMIN_PASSWORD,
        plan=settings.BOOTSTRAP_PIZZARIA_PLAN,
        monthly_message_limit=settings.BOOTSTRAP_PIZZARIA_MONTHLY_MESSAGE_LIMIT,
        copy_default_flows=False,
    )
    yield
    logger.info("Backend API shutdown complete")


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="Core Backend API for orchestrating WhatsApp conversations",
    lifespan=lifespan,
)

_cors_origins = [
    origin.strip()
    for origin in settings.CORS_ORIGINS.split(",")
    if origin.strip()
] or ["*"]
_cors_wildcard = _cors_origins == ["*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=not _cors_wildcard,
    allow_methods=["*"],
    allow_headers=["*"],
)
if settings.TRUST_PROXY:
    from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

    app.add_middleware(ProxyHeadersMiddleware, trusted_hosts=["*"])
app.add_middleware(
    TenantMiddleware,
    default_tenant=settings.DEFAULT_TENANT_ID,
)

app.include_router(health.router)
app.include_router(admin_audit_logs.router)
app.include_router(admin_tenants.router)
app.include_router(admin_users.router)
app.include_router(auth.router)
app.include_router(billing.router)
app.include_router(billing_webhooks.router)
app.include_router(messages.router)
app.include_router(conversations.router)
app.include_router(conversation_groups.router)
app.include_router(quick_replies.router)
app.include_router(usage.router)
app.include_router(fiscal.router)
app.include_router(dashboard.router)
app.include_router(flows_admin.router)
app.include_router(tenant_settings.router)
app.include_router(simulation.router)
app.include_router(subscriptions.router)
app.include_router(conversation_logs.router)
app.include_router(whatsapp_accounts.router)
app.include_router(whatsapp_templates.router)
app.include_router(whatsapp_onboarding.router)
app.include_router(meta_callbacks.router)
app.include_router(internal_whatsapp.router)
app.include_router(flow_routes.router)
app.include_router(actions.router)
app.include_router(leads.router)
app.include_router(proposals.router)


@app.exception_handler(RequestValidationError)
async def request_validation_handler(
    request: Request,
    exc: RequestValidationError,
) -> JSONResponse:
    locations = [err.get("loc") for err in exc.errors()]
    messages = [err.get("msg") for err in exc.errors()]
    logger.warning(
        "Request validation failed %s %s loc=%s msg=%s",
        request.method,
        request.url.path,
        locations,
        messages,
    )
    return JSONResponse(status_code=422, content={"detail": exc.errors()})


@app.get("/")
async def root() -> dict:
    return {
        "service": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "status": "running",
    }


async def _sync_default_flows(flow_service: FlowService, flow_catalog_service: FlowCatalogService) -> None:
    try:
        flows = await flow_service.list_admin_flows(tenant_id=settings.DEFAULT_TENANT_ID)
        for item in flows:
            flow_name = str(item.get("name") or "").strip()
            if not flow_name:
                continue
            yaml_payload = await flow_service.get_admin_flow_yaml(
                flow_name,
                tenant_id=settings.DEFAULT_TENANT_ID,
            )
            yaml_content = str(yaml_payload.get("yaml_content") or "")
            if yaml_content:
                await flow_catalog_service.save_yaml(
                    tenant_id=settings.DEFAULT_TENANT_ID,
                    flow_name=flow_name,
                    yaml_content=yaml_content,
                )
    except Exception as exc:
        logger.warning("Could not sync initial flows to MySQL: %s", exc)


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level=settings.LOG_LEVEL.lower(),
    )

