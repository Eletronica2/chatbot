"""Admin endpoints for WhatsApp message templates."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request

from app.api.access import assert_capability, resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.domain.whatsapp_template import (
    WhatsAppTemplate,
    WhatsAppTemplateCreate,
    WhatsAppTemplateSend,
    WhatsAppTemplateSendResult,
)
from app.services.admin_audit_service import AdminAuditService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    whatsapp_template_service_dependency,
)
from app.services.whatsapp_template_service import WhatsAppTemplateService

router = APIRouter(prefix="/api/v1/tenants/{tenant_id}/whatsapp-templates", tags=["WhatsApp Templates"])


@router.get("", response_model=list[WhatsAppTemplate])
async def list_templates(
    request: Request,
    tenant_id: str,
    account_key: str | None = None,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppTemplateService = Depends(whatsapp_template_service_dependency),
) -> list[WhatsAppTemplate]:
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    try:
        return await service.list_templates(target_tenant_id, account_key=account_key)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("", response_model=WhatsAppTemplate)
async def create_template(
    request: Request,
    tenant_id: str,
    payload: WhatsAppTemplateCreate,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppTemplateService = Depends(whatsapp_template_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> WhatsAppTemplate:
    assert_capability(user, "canManageTemplates")
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    try:
        item = await service.create_template(target_tenant_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await audit_service.append(
        tenant_id=target_tenant_id,
        action="whatsapp_template.create",
        entity_type="whatsapp_template",
        entity_key=item.name,
        summary=f"Modelo WhatsApp {item.name} criado",
        actor=user,
        metadata={"language": item.language, "category": item.category, "status": item.status},
    )
    return item


@router.post("/send", response_model=WhatsAppTemplateSendResult)
async def send_template(
    request: Request,
    tenant_id: str,
    payload: WhatsAppTemplateSend,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppTemplateService = Depends(whatsapp_template_service_dependency),
    audit_service: AdminAuditService = Depends(admin_audit_service_dependency),
) -> WhatsAppTemplateSendResult:
    target_tenant_id = resolve_tenant_scope(user, request, tenant_id)
    try:
        result = await service.send_template(target_tenant_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await audit_service.append(
        tenant_id=target_tenant_id,
        action="whatsapp_template.send_test",
        entity_type="whatsapp_template",
        entity_key=payload.template_name,
        summary=f"Teste de modelo {payload.template_name} enviado",
        actor=user,
        metadata={
            "language": payload.language,
            "to": result.to,
            "message_id": result.message_id,
        },
    )
    return result
