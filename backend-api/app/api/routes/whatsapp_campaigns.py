"""Bulk WhatsApp template campaigns."""
from __future__ import annotations

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from fastapi.responses import Response

from app.api.access import assert_capability, resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.domain.whatsapp_campaign import (
    CampaignConfirmRequest,
    CampaignCreate,
    CampaignDetail,
    CampaignSendReadiness,
    CampaignSummary,
    CampaignValidationResult,
)
from app.services.admin_audit_service import AdminAuditService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    whatsapp_campaign_service_dependency,
)
from app.services.whatsapp_campaign_service import WhatsAppCampaignService

router = APIRouter(prefix="/api/v1/tenants/{tenant_id}/campaigns", tags=["WhatsApp Campaigns"])


@router.get("", response_model=list[CampaignSummary])
async def list_campaigns(
    request: Request,
    tenant_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppCampaignService = Depends(whatsapp_campaign_service_dependency),
) -> list[CampaignSummary]:
    assert_capability(user, "canManageTemplates")
    target = resolve_tenant_scope(user, request, tenant_id)
    return await service.list_campaigns(target)


@router.get("/send-readiness", response_model=CampaignSendReadiness)
async def campaign_send_readiness(
    request: Request,
    tenant_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppCampaignService = Depends(whatsapp_campaign_service_dependency),
) -> CampaignSendReadiness:
    assert_capability(user, "canManageTemplates")
    target = resolve_tenant_scope(user, request, tenant_id)
    return await service.get_send_readiness(target)


@router.get("/{campaign_id}", response_model=CampaignDetail)
async def get_campaign_detail(
    request: Request,
    tenant_id: str,
    campaign_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppCampaignService = Depends(whatsapp_campaign_service_dependency),
) -> CampaignDetail:
    assert_capability(user, "canManageTemplates")
    target = resolve_tenant_scope(user, request, tenant_id)
    try:
        return await service.get_campaign_detail(target, campaign_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.post("", response_model=CampaignSummary)
async def create_campaign(
    request: Request,
    tenant_id: str,
    payload: CampaignCreate,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppCampaignService = Depends(whatsapp_campaign_service_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> CampaignSummary:
    assert_capability(user, "canManageTemplates")
    target = resolve_tenant_scope(user, request, tenant_id)
    try:
        item = await service.create_campaign(target, payload, user_id=user.user_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await audit.append(
        tenant_id=target,
        action="campaign.create",
        entity_type="campaign",
        entity_key=item.id,
        summary=f"Campanha {item.name}",
        actor=user,
        metadata={"template": item.template_name},
    )
    return item


@router.get("/{campaign_id}/import-template.xlsx")
async def download_import_template(
    request: Request,
    tenant_id: str,
    campaign_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppCampaignService = Depends(whatsapp_campaign_service_dependency),
) -> Response:
    assert_capability(user, "canManageTemplates")
    target = resolve_tenant_scope(user, request, tenant_id)
    try:
        raw = await service.build_import_xlsx(target, campaign_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return Response(
        content=raw,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="campanha-{campaign_id}.xlsx"'},
    )


@router.post("/{campaign_id}/validate", response_model=CampaignValidationResult)
async def validate_campaign_upload(
    request: Request,
    tenant_id: str,
    campaign_id: str,
    file: UploadFile = File(...),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppCampaignService = Depends(whatsapp_campaign_service_dependency),
) -> CampaignValidationResult:
    assert_capability(user, "canManageTemplates")
    target = resolve_tenant_scope(user, request, tenant_id)
    raw = await file.read()
    try:
        return await service.validate_upload(target, campaign_id, raw)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/{campaign_id}/start", response_model=CampaignSummary)
async def start_campaign(
    request: Request,
    tenant_id: str,
    campaign_id: str,
    body: CampaignConfirmRequest,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppCampaignService = Depends(whatsapp_campaign_service_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> CampaignSummary:
    assert_capability(user, "canManageTemplates")
    target = resolve_tenant_scope(user, request, tenant_id)
    try:
        item = await service.start_campaign(target, campaign_id, confirm=body.confirm)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await audit.append(
        tenant_id=target,
        action="campaign.start",
        entity_type="campaign",
        entity_key=campaign_id,
        summary="Campanha iniciada",
        actor=user,
    )
    return item


@router.post("/{campaign_id}/pause", response_model=CampaignSummary)
async def pause_campaign(
    request: Request,
    tenant_id: str,
    campaign_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppCampaignService = Depends(whatsapp_campaign_service_dependency),
) -> CampaignSummary:
    assert_capability(user, "canManageTemplates")
    target = resolve_tenant_scope(user, request, tenant_id)
    try:
        return await service.pause_campaign(target, campaign_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/{campaign_id}/results.xlsx")
async def export_campaign_results(
    request: Request,
    tenant_id: str,
    campaign_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppCampaignService = Depends(whatsapp_campaign_service_dependency),
) -> Response:
    assert_capability(user, "canManageTemplates")
    target = resolve_tenant_scope(user, request, tenant_id)
    try:
        raw = await service.build_results_xlsx(target, campaign_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return Response(
        content=raw,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="resultados-{campaign_id}.xlsx"'},
    )


@router.post("/{campaign_id}/cancel", response_model=CampaignSummary)
async def cancel_campaign(
    request: Request,
    tenant_id: str,
    campaign_id: str,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: WhatsAppCampaignService = Depends(whatsapp_campaign_service_dependency),
) -> CampaignSummary:
    assert_capability(user, "canManageTemplates")
    target = resolve_tenant_scope(user, request, tenant_id)
    try:
        return await service.cancel_campaign(target, campaign_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc