"""Order status notifications over WhatsApp: free text inside the 24h window, approved template outside it."""
from __future__ import annotations

import logging
from typing import Any, Dict, Optional

import httpx
from fastapi import HTTPException

from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.domain import orders as order_domain
from app.domain.whatsapp_template import WhatsAppTemplateSend
from app.services.outbound_billing import finalize_outbound, gateway_billing_fields, reserve_outbound

logger = logging.getLogger(__name__)


class OrderNotificationService:
    def __init__(
        self,
        database: MySQLDatabase,
        order_service: Any,
        template_service: Any,
        message_service: Any,
        session_service: Any,
    ) -> None:
        self.db = database
        self.orders = order_service
        self.templates = template_service
        self.messages = message_service
        self.sessions = session_service

    async def window_open(self, tenant_key: str, customer_phone: str) -> bool:
        """True when the customer sent a message in the last 24h (Meta customer service window)."""
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        digits = "".join(ch for ch in str(customer_phone or "") if ch.isdigit())
        row = await self.db.fetch_one_async(
            "SELECT MAX(m.created_at) >= (NOW() - INTERVAL 24 HOUR) AS window_open "
            "FROM messages m INNER JOIN sessions s ON s.id = m.session_id "
            "WHERE m.tenant_id = %s AND m.direction = 'incoming' AND s.phone_number IN (%s, %s)",
            (tenant_pk, digits, f"+{digits}"),
        )
        return bool((row or {}).get("window_open"))

    async def notify_status(
        self, tenant_key: str, order: Dict[str, Any], history_id: int, *, store_name: str,
    ) -> str:
        """Send the status message and record the outcome on the history row. Never raises."""
        status = order["status"]
        if status not in order_domain.NOTIFICATION_TEXTS:
            return await self._record(history_id, "not_applicable")
        try:
            if await self.window_open(tenant_key, order["customer_phone"]):
                text = order_domain.notification_text(
                    status, order["order_number"], store_name,
                    fee_cents=order.get("delivery_fee_cents"), total_cents=order.get("total_cents"),
                )
                message_id = await self._send_text(tenant_key, order, text, history_id)
                return await self._record(history_id, "sent" if message_id else "failed", message_id)
            return await self._send_template(tenant_key, order, history_id)
        except HTTPException as exc:
            code = "blocked_billing" if exc.status_code == 402 else "failed"
            logger.warning("order_notification_%s tenant=%s order=%s", code, tenant_key, order.get("id"))
            return await self._record(history_id, code)
        except Exception:
            logger.exception("order_notification_failed tenant=%s order=%s", tenant_key, order.get("id"))
            return await self._record(history_id, "failed")

    async def _send_text(self, tenant_key: str, order: Dict[str, Any], text: str, history_id: int) -> Optional[str]:
        phone_number_id = order.get("phone_number_id") or None
        billing = await reserve_outbound(
            tenant_key,
            category="SERVICE",
            category_source="order_status_in_window",
            source_path="order_status",
            idempotency_key=f"order_status:{history_id}",
            phone_number_id=phone_number_id,
        )
        message_id: Optional[str] = None
        try:
            async with httpx.AsyncClient(timeout=settings.GATEWAY_API_TIMEOUT) as client:
                response = await client.post(
                    f"{settings.GATEWAY_API_URL}/send-message",
                    headers={"x-internal-api-key": settings.INTERNAL_API_KEY},
                    json={
                        "tenant_id": tenant_key,
                        "to": order["customer_phone"],
                        "text": text,
                        "phone_number_id": phone_number_id,
                        **gateway_billing_fields(billing),
                    },
                )
            if response.status_code == 200:
                message_id = (response.json() or {}).get("message_id")
        except httpx.RequestError:
            logger.warning("order_notification_gateway_unreachable tenant=%s", tenant_key)
        finally:
            await finalize_outbound(tenant_key, billing, provider_message_id=message_id)
        if message_id:
            await self._append_to_conversation(tenant_key, order, text, message_id)
        return message_id

    async def _send_template(self, tenant_key: str, order: Dict[str, Any], history_id: int) -> str:
        payload = WhatsAppTemplateSend(
            template_name=settings.ORDER_STATUS_TEMPLATE_NAME,
            language=settings.ORDER_STATUS_TEMPLATE_LANGUAGE,
            to=order["customer_phone"],
            body_parameters=[str(order["order_number"]), order_domain.STATUS_LABELS[order["status"]]],
        )
        try:
            result = await self.templates.send_template(tenant_key, payload)
        except ValueError as exc:
            # No approved template (or recipient not allowed): the message is not sent outside the window.
            logger.info("order_notification_skipped_outside_window tenant=%s reason=%s", tenant_key, str(exc)[:120])
            return await self._record(history_id, "skipped_outside_window")
        return await self._record(history_id, "sent_template" if result.message_id else "failed", result.message_id)

    async def _append_to_conversation(self, tenant_key: str, order: Dict[str, Any], text: str, message_id: str) -> None:
        try:
            session = await self.sessions.get_or_create_session(tenant_key, order["customer_phone"])
            await self.messages.append(
                tenant_id=tenant_key,
                session_id=session.session_id,
                direction="outgoing",
                role="assistant",
                content=text,
                source="system",
                metadata={"source": "order_status", "order_id": order["id"], "provider_message_id": message_id},
                phone_number_id=session.phone_number_id,
            )
        except Exception:
            logger.exception("order_notification_history_failed tenant=%s", tenant_key)

    async def _record(self, history_id: int, status: str, message_id: Optional[str] = None) -> str:
        await self.orders.record_notification(history_id, status, message_id)
        return status
