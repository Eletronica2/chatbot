"""Orders API: list, detail with items/history, status changes with WhatsApp notification."""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from app.api.access import assert_capability, resolve_tenant_scope
from app.domain import orders as order_domain
from app.domain.auth import AuthenticatedUser
from app.services.admin_audit_service import AdminAuditService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    order_notification_service_dependency,
    order_service_dependency,
    tenant_settings_service_dependency,
)
from app.services.order_notification_service import OrderNotificationService
from app.services.order_service import OrderConflict, OrderError, OrderNotFound, OrderService
from app.services.tenant_settings_service import TenantSettingsService

router = APIRouter(prefix="/api/v1/orders", tags=["Orders"])


class StatusPayload(BaseModel):
    status: str = Field(..., min_length=2, max_length=32)
    note: Optional[str] = Field(None, max_length=300)
    notify: bool = True


class DeliveryFeePayload(BaseModel):
    fee_cents: int = Field(..., ge=0, le=1_000_000)
    notify: bool = True


def _http(exc: Exception) -> HTTPException:
    if isinstance(exc, OrderNotFound):
        return HTTPException(status_code=404, detail=str(exc))
    if isinstance(exc, OrderConflict):
        return HTTPException(status_code=409, detail=str(exc))
    return HTTPException(status_code=422, detail=str(exc))


@router.get("/meta")
async def orders_meta(
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    settings_service: TenantSettingsService = Depends(tenant_settings_service_dependency),
) -> Dict[str, Any]:
    tenant_id = resolve_tenant_scope(user, request)
    settings = await settings_service.get_or_create(tenant_id)
    return {
        "orders_enabled": settings.orders_enabled,
        "statuses": [{"value": k, "label": v} for k, v in order_domain.STATUS_LABELS.items()],
        "fulfillments": list(order_domain.FULFILLMENTS),
    }


@router.get("")
async def list_orders(
    request: Request,
    status: Optional[str] = Query(None, max_length=32),
    active_only: bool = False,
    limit: int = Query(100, ge=1, le=300),
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: OrderService = Depends(order_service_dependency),
) -> List[Dict[str, Any]]:
    assert_capability(user, "canViewOrders")
    tenant_id = resolve_tenant_scope(user, request)
    try:
        return await service.list(tenant_id, status=status, active_only=active_only, limit=limit)
    except OrderError as exc:
        raise _http(exc) from exc


@router.get("/{order_id}")
async def get_order(
    order_id: int,
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: OrderService = Depends(order_service_dependency),
) -> Dict[str, Any]:
    assert_capability(user, "canViewOrders")
    tenant_id = resolve_tenant_scope(user, request)
    try:
        return await service.get(tenant_id, order_id)
    except OrderNotFound as exc:
        raise _http(exc) from exc


@router.post("/{order_id}/status")
async def update_order_status(
    order_id: int,
    payload: StatusPayload,
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: OrderService = Depends(order_service_dependency),
    notifications: OrderNotificationService = Depends(order_notification_service_dependency),
    settings_service: TenantSettingsService = Depends(tenant_settings_service_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> Dict[str, Any]:
    assert_capability(user, "canUpdateOrders")
    tenant_id = resolve_tenant_scope(user, request)
    try:
        order, history_id, previous = await service.update_status(
            tenant_id, order_id, payload.status, actor_type="user", actor_user_id=str(user.user_id or ""),
            actor_name=user.display_name, note=payload.note or "",
        )
    except (OrderError, OrderNotFound, OrderConflict) as exc:
        raise _http(exc) from exc
    notification = "not_requested"
    if payload.notify:
        settings = await settings_service.get_or_create(tenant_id)
        notification = await notifications.notify_status(tenant_id, order, history_id, store_name=settings.tenant_name)
    else:
        await service.record_notification(history_id, notification)
    await audit.append(
        tenant_id=tenant_id, action="order.status.update", entity_type="order", entity_key=str(order_id),
        summary=f"Pedido #{order['order_number']}: {order_domain.STATUS_LABELS.get(previous, previous)} → "
                f"{order['status_label']}",
        actor=user, metadata={"from": previous, "to": order["status"], "notification": notification},
    )
    detail = await service.get(tenant_id, order_id)
    return {"order": detail, "notification_status": notification}


@router.post("/{order_id}/delivery-fee")
async def set_delivery_fee(
    order_id: int,
    payload: DeliveryFeePayload,
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    service: OrderService = Depends(order_service_dependency),
    notifications: OrderNotificationService = Depends(order_notification_service_dependency),
    settings_service: TenantSettingsService = Depends(tenant_settings_service_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> Dict[str, Any]:
    """Store informs the delivery fee; the backend recomputes the total and asks the customer to accept it."""
    assert_capability(user, "canUpdateOrders")
    tenant_id = resolve_tenant_scope(user, request)
    try:
        order, history_id, previous = await service.set_delivery_fee(
            tenant_id, order_id, payload.fee_cents, actor_user_id=str(user.user_id or ""),
            actor_name=user.display_name,
        )
    except (OrderError, OrderNotFound, OrderConflict) as exc:
        raise _http(exc) from exc
    notification = "not_requested"
    if payload.notify:
        settings = await settings_service.get_or_create(tenant_id)
        notification = await notifications.notify_status(tenant_id, order, history_id, store_name=settings.tenant_name)
    else:
        await service.record_notification(history_id, notification)
    await audit.append(
        tenant_id=tenant_id, action="order.delivery_fee.set", entity_type="order", entity_key=str(order_id),
        summary=f"Pedido #{order['order_number']}: taxa {order_domain.money(payload.fee_cents)}, "
                f"total {order_domain.money(order['total_cents'])}",
        actor=user, metadata={"from": previous, "fee_cents": payload.fee_cents, "total_cents": order["total_cents"],
                              "notification": notification},
    )
    return {"order": await service.get(tenant_id, order_id), "notification_status": notification}
