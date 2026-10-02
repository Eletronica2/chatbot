"""BillingGate helpers for backend-initiated outbound (manual reply, template, system)."""
from __future__ import annotations

import asyncio
import logging
from typing import Any

from fastapi import HTTPException

from app.services.dependencies import get_billing_gate

logger = logging.getLogger(__name__)


def _gate():
    try:
        return get_billing_gate()
    except RuntimeError:
        return None


async def reserve_outbound(
    tenant_id: str,
    *,
    category: str,
    category_source: str,
    source_path: str,
    idempotency_key: str,
    phone_number_id: str | None = None,
    template_name: str | None = None,
) -> dict[str, Any]:
    """Return the billing fields the gateway requires; raise 402 when blocked."""
    gate = _gate()
    if gate is None or not gate.enabled:
        return {"billing_enforced": False}
    decision = await asyncio.to_thread(
        gate.reserve,
        tenant_id,
        category=category,
        category_source=category_source,
        source_path=source_path,
        idempotency_key=idempotency_key,
        phone_number_id=phone_number_id,
        template_name=template_name,
    )
    if not decision.allowed:
        raise HTTPException(
            status_code=402,
            detail={"code": decision.code, "message": decision.message or "Envio bloqueado pelo billing"},
        )
    return {
        "billing_enforced": True,
        "billing_reservation_id": decision.reservation_id,
        "billing_mode": decision.billing_mode,
        "billing_level": decision.level,
    }


async def finalize_outbound(tenant_id: str, billing: dict[str, Any], *, provider_message_id: str | None) -> None:
    """Mark accepted when Meta returned a wamid; release when the send never happened."""
    reservation_id = billing.get("billing_reservation_id")
    gate = _gate()
    if not reservation_id or gate is None:
        return
    try:
        if provider_message_id:
            await asyncio.to_thread(gate.mark_accepted, tenant_id, reservation_id, provider_message_id)
        else:
            await asyncio.to_thread(gate.release, tenant_id, reservation_id, reason="send_failed")
    except Exception:
        logger.exception("billing_finalize_failed tenant=%s reservation=%s", tenant_id, reservation_id)


def gateway_billing_fields(billing: dict[str, Any]) -> dict[str, Any]:
    return {
        "billing_enforced": bool(billing.get("billing_enforced")),
        "billing_reservation_id": billing.get("billing_reservation_id"),
    }
