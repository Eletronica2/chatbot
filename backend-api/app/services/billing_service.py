"""Billing service with Stripe Checkout, portal and webhook synchronization."""
from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import logging
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any

import httpx

from app.config.settings import Settings
from app.db.mysql import MySQLDatabase
from app.domain.billing import (
    BillingCheckoutSession,
    BillingCustomerSnapshot,
    BillingInvoiceSnapshot,
    BillingPortalSession,
    BillingSummary,
)
from app.domain.subscription import TenantSubscription, map_subscription_to_tenant_status
from app.services.email_service import EmailService

logger = logging.getLogger(__name__)

_PLAN_PRICES_CENTS = {
    "starter": 9900,
    "growth": 24900,
    "pro": 59900,
    "enterprise": 149900,
    "on_demand": 0,  # usage-based; billed via Stripe meters
}


class BillingService:
    def __init__(
        self,
        *,
        database: MySQLDatabase,
        settings: Settings,
        email_service: EmailService | None = None,
    ):
        self.database = database
        self.settings = settings
        self.email_service = email_service
        self._base_url = "https://api.stripe.com/v1"
        self.billing_gate = None
        self.topup_service = None

    @property
    def stripe_test_mode(self) -> bool:
        return self.settings.STRIPE_SECRET_KEY.strip().startswith(("sk_test_", "rk_test_"))

    @property
    def stripe_live_key(self) -> bool:
        return self.settings.STRIPE_SECRET_KEY.strip().startswith(("sk_live_", "rk_live_"))

    @property
    def stripe_charging_allowed(self) -> bool:
        """TEST keys always; a LIVE key only with STRIPE_ALLOW_LIVE=true (owner authorization)."""
        return self.stripe_test_mode or (self.stripe_live_key and bool(self.settings.STRIPE_ALLOW_LIVE))

    def _assert_charging_allowed(self) -> None:
        if self.stripe_live_key and not self.settings.STRIPE_ALLOW_LIVE:
            raise ValueError("Stripe LIVE não autorizado neste ambiente")

    def _v2_plan(self, plan: str) -> dict[str, Any] | None:
        """Active Catalog V2 plan with a fixed price and allowance (what the panel sells)."""
        catalog = getattr(self.billing_gate, "catalog", None)
        if catalog is None or not plan:
            return None
        item = catalog.get_item(plan.strip().upper())
        if item and item["kind"] == "plan" and item["status"] == "active" and item.get("price") \
                and int(item.get("operational_units") or 0) > 0:
            return item
        return None

    def v2_plans(self) -> list[dict[str, Any]]:
        catalog = getattr(self.billing_gate, "catalog", None)
        if catalog is None:
            return []
        return [
            {"code": i["code"], "label": i["label"], "price": str(i["price"]),
             "operational_units": int(i["operational_units"] or 0)}
            for i in catalog.list_items()
            if i["kind"] == "plan" and i.get("price") and int(i.get("operational_units") or 0) > 0
        ]

    async def create_topup_checkout(self, *, tenant_id: str, purchase: dict[str, Any]) -> dict[str, Any]:
        if not self.stripe_charging_allowed:
            return {"checkout_url": None, "status": "pending", "reason": "stripe_test_not_configured"}
        cents = int((Decimal(purchase["total_amount"]) * 100).to_integral_value())
        data = await self._stripe_post(
            "/checkout/sessions",
            {
                "mode": "payment",
                "client_reference_id": tenant_id,
                "success_url": self.settings.BILLING_SUCCESS_URL,
                "cancel_url": self.settings.BILLING_CANCEL_URL,
                "line_items[0][price_data][currency]": "brl",
                "line_items[0][price_data][unit_amount]": str(cents),
                "line_items[0][price_data][product_data][name]": f"{purchase['catalog_item_code']} x{purchase['units']}",
                "line_items[0][quantity]": "1",
                "metadata[tenant_id]": tenant_id,
                "metadata[purchase_id]": purchase["id"],
                "metadata[kind]": "billing_v2_topup",
            },
        )
        session_id = str(data.get("id") or "")
        if session_id and self.topup_service is not None:
            await asyncio.to_thread(self.topup_service.attach_session, purchase["id"], session_id)
        return {"checkout_url": data.get("url"), "session_id": session_id, "status": "pending"}

    async def _grant_topup_from_checkout(self, session: dict[str, Any], *, livemode: bool) -> None:
        metadata = session.get("metadata") or {}
        purchase_id = str(metadata.get("purchase_id") or "").strip()
        if not purchase_id or self.topup_service is None:
            return
        if livemode and not (self.stripe_live_key and self.settings.STRIPE_ALLOW_LIVE):
            logger.error("billing_v2_topup_livemode_rejected purchase=%s", purchase_id)
            return
        if str(session.get("payment_status") or "") != "paid":
            logger.info("billing_v2_topup_not_paid purchase=%s status=%s", purchase_id, session.get("payment_status"))
            return
        tenant_key = str(metadata.get("tenant_id") or "").strip()
        tenant_row = self.database.get_tenant_record(tenant_key) if tenant_key else None
        if not tenant_row:
            logger.error("billing_v2_topup_unknown_tenant purchase=%s", purchase_id)
            return
        amount_total = session.get("amount_total")
        expected = (Decimal(int(amount_total)) / 100) if amount_total is not None else None
        result = await asyncio.to_thread(
            self.topup_service.mark_paid_and_grant,
            purchase_id,
            provider_payment_id=str(session.get("payment_intent") or "") or None,
            actor_id=None,
            reason="stripe_test_webhook",
            expected_tenant_pk=int(tenant_row["id"]),
            expected_total=expected,
        )
        logger.info("billing_v2_topup_granted purchase=%s created=%s", purchase_id, result.get("created"))

    async def _activate_v2_plan(self, tenant_id: str, plan_code: str) -> None:
        """Paid subscription: assign the V2 plan (idempotent) and grant this cycle's allowance."""
        if self.billing_gate is None or not self._v2_plan(plan_code):
            return
        tenant_row = self.database.get_tenant_record(tenant_id)
        if not tenant_row:
            return
        tenant_pk = int(tenant_row["id"])
        config = await asyncio.to_thread(self.billing_gate.get_config, tenant_pk)
        if config.get("plan_code") == plan_code.strip().upper():
            await asyncio.to_thread(self.billing_gate.ensure_cycle_grant, tenant_pk, require_paid=False)
            return
        await asyncio.to_thread(self.billing_gate.configure_plan, tenant_pk, plan_code=plan_code.strip().upper(),
                                actor_id=None)
        logger.info("billing_v2_plan_activated_by_payment tenant=%s plan=%s", tenant_id, plan_code)

    async def _ensure_v2_cycle_grant(self, tenant_id: str) -> None:
        if self.billing_gate is None:
            return
        tenant_row = self.database.get_tenant_record(tenant_id)
        if not tenant_row:
            return
        await asyncio.to_thread(self.billing_gate.ensure_cycle_grant, int(tenant_row["id"]), require_paid=False)

    @property
    def provider_ready(self) -> bool:
        return (
            self.settings.BILLING_PROVIDER.strip().lower() == "stripe"
            and bool(self.settings.STRIPE_SECRET_KEY.strip())
        )

    def available_plans(self) -> list[str]:
        return [plan for plan in ("starter", "growth", "pro", "enterprise", "on_demand")]

    def estimate_plan_mrr_cents(self, plan: str) -> int:
        return _PLAN_PRICES_CENTS.get(plan.strip().lower(), 0)

    async def create_checkout_session(
        self,
        *,
        tenant_id: str,
        tenant_name: str,
        customer_email: str,
        customer_name: str,
        plan: str,
    ) -> BillingCheckoutSession:
        self._assert_provider_ready()
        self._assert_charging_allowed()
        snapshot = await self.get_customer_snapshot(tenant_id)
        if snapshot and snapshot.provider_subscription_id and snapshot.status in {"active", "trialing", "past_due"}:
            raise ValueError("Esta empresa já tem uma assinatura. Use o portal de cobrança para pagamento ou cancelamento.")
        v2_item = self._v2_plan(plan)
        price_id = None if v2_item else self._price_id_for_plan(plan)
        customer_id = await self._find_or_create_customer(
            tenant_id=tenant_id,
            tenant_name=tenant_name,
            customer_email=customer_email,
            customer_name=customer_name,
        )
        payload = {
            "mode": "subscription",
            "customer": customer_id,
            "client_reference_id": tenant_id,
            "success_url": self.settings.BILLING_SUCCESS_URL,
            "cancel_url": self.settings.BILLING_CANCEL_URL,
            "metadata[tenant_id]": tenant_id,
            "metadata[plan]": plan,
            "line_items[0][quantity]": "1",
            "subscription_data[metadata][tenant_id]": tenant_id,
            "subscription_data[metadata][plan]": plan,
        }
        if v2_item:
            # Price comes from Catalog V2 (single source); the webhook assigns the plan only once paid.
            cents = int((Decimal(str(v2_item["price"])) * 100).to_integral_value())
            payload.update({
                "line_items[0][price_data][currency]": "brl",
                "line_items[0][price_data][unit_amount]": str(cents),
                "line_items[0][price_data][recurring][interval]": "month",
                "line_items[0][price_data][product_data][name]": f"Atende Ai — Plano {v2_item['label']}",
                "metadata[plan_code]": v2_item["code"],
                "subscription_data[metadata][plan_code]": v2_item["code"],
            })
            plan = v2_item["code"]
        else:
            payload["line_items[0][price]"] = price_id
        data = await self._stripe_post("/checkout/sessions", payload)
        checkout = BillingCheckoutSession(
            provider="stripe",
            checkout_url=str(data.get("url") or ""),
            session_id=str(data.get("id") or ""),
            plan=plan,
        )
        if checkout.checkout_url:
            await self._touch_customer_checkout_url(
                tenant_id=tenant_id,
                provider_customer_id=customer_id,
                checkout_url=checkout.checkout_url,
            )
        return checkout

    async def create_portal_session(
        self,
        *,
        tenant_id: str,
        return_url: str | None = None,
    ) -> BillingPortalSession:
        self._assert_provider_ready()
        snapshot = await self.get_customer_snapshot(tenant_id)
        if snapshot is None or not snapshot.provider_customer_id:
            raise ValueError("Tenant ainda nao possui customer no provedor de billing")
        data = await self._stripe_post(
            "/billing_portal/sessions",
            {
                "customer": snapshot.provider_customer_id,
                "return_url": return_url or self.settings.BILLING_PORTAL_RETURN_URL,
            },
        )
        portal = BillingPortalSession(
            provider="stripe",
            portal_url=str(data.get("url") or ""),
        )
        await self._touch_customer_portal_url(
            tenant_id=tenant_id,
            provider_customer_id=snapshot.provider_customer_id,
            portal_url=portal.portal_url,
        )
        return portal

    async def get_summary(
        self,
        *,
        tenant_id: str,
        subscription: TenantSubscription,
        usage: dict[str, int | str],
    ) -> BillingSummary:
        return BillingSummary(
            tenant_id=tenant_id,
            provider="stripe",
            provider_ready=self.provider_ready,
            subscription_status=subscription.status,
            current_plan=subscription.plan,
            renewal_date=subscription.renewal_date,
            monthly_message_limit=subscription.monthly_message_limit,
            used_messages=int(usage.get("used_messages") or 0),
            remaining_messages=int(usage.get("remaining_messages") or 0),
            grace_days=max(self.settings.BILLING_GRACE_DAYS, 0),
            customer=await self.get_customer_snapshot(tenant_id),
            invoices=await self.list_invoices(tenant_id, limit=8),
            available_plans=self.available_plans(),
        )

    async def get_customer_snapshot(self, tenant_id: str) -> BillingCustomerSnapshot | None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _load() -> BillingCustomerSnapshot | None:
            row = self.database.fetch_one(
                """
                SELECT provider, provider_customer_id, provider_subscription_id, provider_price_id,
                       status, current_period_end, checkout_url, portal_url, created_at, updated_at
                FROM billing_customers
                WHERE tenant_id = %s
                LIMIT 1
                """,
                (tenant_pk,),
            )
            if row is None:
                return None
            return BillingCustomerSnapshot(
                tenant_id=tenant_id,
                provider=str(row.get("provider") or "stripe"),
                provider_customer_id=str(row.get("provider_customer_id") or ""),
                provider_subscription_id=row.get("provider_subscription_id"),
                provider_price_id=row.get("provider_price_id"),
                status=str(row.get("status") or "inactive"),
                current_period_end=row.get("current_period_end"),
                checkout_url=row.get("checkout_url"),
                portal_url=row.get("portal_url"),
                created_at=row.get("created_at"),
                updated_at=row.get("updated_at"),
            )

        return await asyncio.to_thread(_load)

    async def list_invoices(self, tenant_id: str, limit: int = 10) -> list[BillingInvoiceSnapshot]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _load() -> list[BillingInvoiceSnapshot]:
            rows = self.database.fetch_all(
                """
                SELECT provider_invoice_id, provider_subscription_id, status,
                       hosted_invoice_url, invoice_pdf_url, amount_due, amount_paid,
                       currency, due_date, paid_at, created_at
                FROM billing_invoices
                WHERE tenant_id = %s
                ORDER BY created_at DESC
                LIMIT %s
                """,
                (tenant_pk, limit),
            )
            return [
                BillingInvoiceSnapshot(
                    tenant_id=tenant_id,
                    provider_invoice_id=str(row.get("provider_invoice_id") or ""),
                    provider_subscription_id=row.get("provider_subscription_id"),
                    status=str(row.get("status") or "draft"),
                    hosted_invoice_url=row.get("hosted_invoice_url"),
                    invoice_pdf_url=row.get("invoice_pdf_url"),
                    amount_due=int(row.get("amount_due") or 0),
                    amount_paid=int(row.get("amount_paid") or 0),
                    currency=str(row.get("currency") or "brl"),
                    due_date=row.get("due_date"),
                    paid_at=row.get("paid_at"),
                    created_at=row.get("created_at"),
                )
                for row in rows
            ]

        return await asyncio.to_thread(_load)

    async def handle_webhook(self, *, payload: bytes, signature: str | None) -> dict[str, Any]:
        if not self.settings.STRIPE_WEBHOOK_SECRET.strip():
            raise ValueError("Stripe webhook secret nao configurado")
        event = self._verify_stripe_signature(payload, signature or "")
        event_type = str(event.get("type") or "")
        data = ((event.get("data") or {}).get("object") or {})

        if event_type == "checkout.session.completed" and (data.get("metadata") or {}).get("purchase_id"):
            await self._grant_topup_from_checkout(data, livemode=bool(event.get("livemode")))
        elif event_type == "checkout.session.completed":
            await self._handle_checkout_completed(data)
        elif event_type in {"customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted"}:
            await self._handle_subscription_event(data)
        elif event_type in {"invoice.paid", "invoice.payment_failed"}:
            await self._handle_invoice_event(data, event_type=event_type)

        return {"received": True, "event_type": event_type}

    async def _handle_checkout_completed(self, session: dict[str, Any]) -> None:
        metadata = session.get("metadata") or {}
        tenant_id = str(metadata.get("tenant_id") or session.get("client_reference_id") or "").strip()
        if not tenant_id:
            return
        subscription_id = str(session.get("subscription") or "").strip() or None
        customer_id = str(session.get("customer") or "").strip() or None
        paid = str(session.get("payment_status") or "") == "paid"
        if customer_id:
            await self._upsert_customer_record(
                tenant_id=tenant_id,
                provider_customer_id=customer_id,
                provider_subscription_id=subscription_id,
                provider_price_id=None,
                status="active" if paid else "inactive",
                current_period_end=None,
            )
        plan_code = str(metadata.get("plan_code") or "").strip()
        if paid and plan_code and self._v2_plan(plan_code):
            await self._sync_subscription_record(
                tenant_id=tenant_id, plan=self._v2_plan(plan_code)["plan_key"] or plan_code.lower(),
                status="active", renewal_date=None,
            )
            await self._activate_v2_plan(tenant_id, plan_code)

    async def _handle_subscription_event(self, subscription: dict[str, Any]) -> None:
        metadata = subscription.get("metadata") or {}
        tenant_id = str(metadata.get("tenant_id") or "").strip()
        if not tenant_id:
            customer_id = str(subscription.get("customer") or "").strip()
            tenant_id = await self._find_tenant_id_by_customer(customer_id)
        if not tenant_id:
            return

        stripe_status = str(subscription.get("status") or "inactive")
        mapped_status = self._map_subscription_status(stripe_status)
        current_period_end = self._from_unix(self._subscription_period_end(subscription))
        price_id = None
        items = (((subscription.get("items") or {}).get("data")) or [])
        if items:
            price_id = (((items[0] or {}).get("price")) or {}).get("id")

        await self._upsert_customer_record(
            tenant_id=tenant_id,
            provider_customer_id=str(subscription.get("customer") or ""),
            provider_subscription_id=str(subscription.get("id") or ""),
            provider_price_id=str(price_id or "") or None,
            status=mapped_status,
            current_period_end=current_period_end,
        )
        v2_item = self._v2_plan(str(metadata.get("plan_code") or ""))
        await self._sync_subscription_record(
            tenant_id=tenant_id,
            plan=(v2_item["plan_key"] if v2_item else None)
            or self._plan_for_price_id(str(price_id or "")) or str(metadata.get("plan") or "starter"),
            status=mapped_status,
            renewal_date=current_period_end,
        )

    async def _handle_invoice_event(self, invoice: dict[str, Any], *, event_type: str) -> None:
        customer_id = str(invoice.get("customer") or "").strip()
        tenant_id = await self._find_tenant_id_by_customer(customer_id)
        if not tenant_id:
            tenant_id = str(((invoice.get("metadata") or {}).get("tenant_id")) or "").strip()
        if not tenant_id:
            return

        amount_due = int(invoice.get("amount_due") or 0)
        amount_paid = int(invoice.get("amount_paid") or 0)
        due_date = self._from_unix(invoice.get("due_date"))
        paid_at = self._from_unix((invoice.get("status_transitions") or {}).get("paid_at"))
        status = "paid" if event_type == "invoice.paid" else "past_due"
        subscription_id, subscription_metadata = self._invoice_subscription(invoice)
        await self._upsert_invoice_record(
            tenant_id=tenant_id,
            provider_invoice_id=str(invoice.get("id") or ""),
            provider_subscription_id=subscription_id,
            status=status,
            hosted_invoice_url=invoice.get("hosted_invoice_url"),
            invoice_pdf_url=invoice.get("invoice_pdf"),
            amount_due=amount_due,
            amount_paid=amount_paid,
            currency=str(invoice.get("currency") or self.settings.STRIPE_DEFAULT_CURRENCY),
            due_date=due_date,
            paid_at=paid_at,
        )

        if event_type == "invoice.payment_failed":
            next_renewal = due_date or (datetime.utcnow() + timedelta(days=self.settings.BILLING_GRACE_DAYS))
            await self._sync_subscription_record(
                tenant_id=tenant_id,
                plan=None,
                status="past_due",
                renewal_date=next_renewal,
            )
            await self._notify_billing_failure(tenant_id)
        elif event_type == "invoice.paid":
            line_items = ((invoice.get("lines") or {}).get("data")) or []
            first_line = line_items[0] if line_items else {}
            next_renewal = self._from_unix(
                (first_line.get("period") or {}).get("end")
            )
            await self._sync_subscription_record(
                tenant_id=tenant_id,
                plan=None,
                status="active",
                renewal_date=next_renewal,
            )
            sub_meta = subscription_metadata or first_line.get("metadata") or {}
            plan_code = str(sub_meta.get("plan_code") or "").strip()
            if plan_code:
                await self._activate_v2_plan(tenant_id, plan_code)
            else:
                await self._ensure_v2_cycle_grant(tenant_id)

    @staticmethod
    def _subscription_period_end(subscription: dict[str, Any]) -> Any:
        """API ≥ 2025-03-31 (basil, incl. 2026-09-30.endive) moved current_period_end to the subscription items."""
        if subscription.get("current_period_end"):
            return subscription["current_period_end"]
        items = ((subscription.get("items") or {}).get("data")) or []
        return (items[0] or {}).get("current_period_end") if items else None

    @staticmethod
    def _invoice_subscription(invoice: dict[str, Any]) -> tuple[str | None, dict[str, Any]]:
        """Subscription id and metadata of an invoice: top level (old API) or parent.subscription_details (basil+)."""
        details = ((invoice.get("parent") or {}).get("subscription_details")) or invoice.get("subscription_details") or {}
        raw = invoice.get("subscription") or details.get("subscription")
        if isinstance(raw, dict):
            raw = raw.get("id")
        return (str(raw) if raw else None), dict(details.get("metadata") or {})

    async def _notify_billing_failure(self, tenant_id: str) -> None:
        if self.email_service is None:
            return
        tenant_row = self.database.get_tenant_record(tenant_id) or {}
        email = str(tenant_row.get("email") or "").strip()
        name = str(tenant_row.get("name") or tenant_id)
        if not email:
            return
        await self.email_service.send_billing_event_email(
            tenant_id=tenant_id,
            tenant_name=name,
            to_email=email,
            subject="Pagamento pendente do plano do chatbot",
            body=(
                "Detectamos uma falha no pagamento da sua assinatura. "
                "Atualize o meio de pagamento no portal de cobranca para evitar bloqueio automatico."
            ),
        )

    def _assert_provider_ready(self) -> None:
        if not self.provider_ready:
            raise ValueError("Stripe nao configurado neste ambiente")

    def _price_id_for_plan(self, plan: str) -> str:
        mapping = {
            "starter": self.settings.STRIPE_PRICE_STARTER,
            "growth": self.settings.STRIPE_PRICE_GROWTH,
            "pro": self.settings.STRIPE_PRICE_PRO,
            "enterprise": self.settings.STRIPE_PRICE_ENTERPRISE,
            "on_demand": getattr(self.settings, "STRIPE_ON_DEMAND_PRICE_ID", "") or "",
        }
        price_id = str(mapping.get(plan.strip().lower()) or "").strip()
        if not price_id:
            raise ValueError(f"Price ID do plano {plan} nao configurado")
        return price_id

    def _plan_for_price_id(self, price_id: str) -> str | None:
        if not price_id:
            return None
        mapping = {
            self.settings.STRIPE_PRICE_STARTER: "starter",
            self.settings.STRIPE_PRICE_GROWTH: "growth",
            self.settings.STRIPE_PRICE_PRO: "pro",
            self.settings.STRIPE_PRICE_ENTERPRISE: "enterprise",
        }
        on_demand_price = str(getattr(self.settings, "STRIPE_ON_DEMAND_PRICE_ID", "") or "").strip()
        if on_demand_price:
            mapping[on_demand_price] = "on_demand"
        return mapping.get(price_id)

    async def report_meter_event(
        self,
        tenant_id: str,
        provider_message_id: str,
        quantity: int = 1,
    ) -> dict[str, Any]:
        """Report a Stripe meter event for usage-based billing.

        NEVER raises to the WhatsApp path — failures are logged and marked pending.
        """
        try:
            meter_name = str(getattr(self.settings, "STRIPE_METER_EVENT_NAME", "") or "").strip()
            if not self.provider_ready or not meter_name:
                await self._mark_usage_stripe(
                    tenant_id,
                    provider_message_id,
                    status="pending",
                )
                return {"reported": False, "status": "pending", "reason": "meter_not_configured"}

            snapshot = await self.get_customer_snapshot(tenant_id)
            customer_id = snapshot.provider_customer_id if snapshot else ""
            if not customer_id:
                await self._mark_usage_stripe(
                    tenant_id,
                    provider_message_id,
                    status="pending",
                )
                return {"reported": False, "status": "pending", "reason": "no_customer"}

            payload = {
                "event_name": meter_name,
                "payload[stripe_customer_id]": customer_id,
                "payload[value]": str(max(int(quantity), 1)),
                "identifier": f"{tenant_id}:{provider_message_id}",
            }
            data = await self._stripe_post("/billing/meter_events", payload)
            meter_event_id = str(data.get("identifier") or data.get("id") or "")
            await self._mark_usage_stripe(
                tenant_id,
                provider_message_id,
                status="reported",
                meter_event_id=meter_event_id or None,
            )
            return {"reported": True, "status": "reported", "meter_event_id": meter_event_id}
        except Exception as exc:
            logger.warning(
                "Stripe meter event failed tenant=%s msg=%s: %s",
                tenant_id,
                provider_message_id,
                exc,
            )
            try:
                await self._mark_usage_stripe(
                    tenant_id,
                    provider_message_id,
                    status="pending",
                )
            except Exception:
                pass
            return {"reported": False, "status": "pending", "reason": "error"}

    async def _mark_usage_stripe(
        self,
        tenant_id: str,
        provider_message_id: str,
        *,
        status: str,
        meter_event_id: str | None = None,
    ) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _write() -> None:
            self.database.execute(
                """
                UPDATE usage_events
                SET stripe_status = %s,
                    stripe_meter_event_id = COALESCE(%s, stripe_meter_event_id)
                WHERE tenant_id = %s
                  AND provider_message_id = %s
                  AND event_type = 'delivered'
                """,
                (status, meter_event_id, tenant_pk, provider_message_id),
            )

        await asyncio.to_thread(_write)

    async def _find_or_create_customer(
        self,
        *,
        tenant_id: str,
        tenant_name: str,
        customer_email: str,
        customer_name: str,
    ) -> str:
        snapshot = await self.get_customer_snapshot(tenant_id)
        if snapshot is not None and snapshot.provider_customer_id:
            return snapshot.provider_customer_id

        data = await self._stripe_post(
            "/customers",
            {
                "email": customer_email,
                "name": customer_name or tenant_name,
                "metadata[tenant_id]": tenant_id,
                "metadata[tenant_name]": tenant_name,
            },
        )
        customer_id = str(data.get("id") or "")
        await self._upsert_customer_record(
            tenant_id=tenant_id,
            provider_customer_id=customer_id,
            provider_subscription_id=None,
            provider_price_id=None,
            status="inactive",
            current_period_end=None,
        )
        return customer_id

    async def _stripe_post(self, path: str, form: dict[str, str]) -> dict[str, Any]:
        async with httpx.AsyncClient(timeout=25.0) as client:
            response = await client.post(
                f"{self._base_url}{path}",
                data=form,
                headers={
                    "Authorization": f"Bearer {self.settings.STRIPE_SECRET_KEY}",
                },
            )
            if response.status_code >= 400:
                try:
                    error = (response.json().get("error") or {})
                except ValueError:
                    error = {}
                logger.warning("stripe_api_error path=%s status=%s type=%s code=%s", path, response.status_code,
                               error.get("type"), error.get("code"))
                raise ValueError(f"Stripe recusou a operação: {error.get('message') or response.status_code}")
            return response.json()

    def _verify_stripe_signature(self, payload: bytes, signature_header: str) -> dict[str, Any]:
        fragments = {}
        for piece in signature_header.split(","):
            if "=" not in piece:
                continue
            key, value = piece.split("=", 1)
            fragments.setdefault(key.strip(), []).append(value.strip())
        timestamp = str((fragments.get("t") or [""])[0])
        signatures = fragments.get("v1") or []
        if not timestamp or not signatures:
            raise ValueError("Stripe signature ausente")
        # Stripe's recommended tolerance: an old (replayed) signed event is rejected.
        if not timestamp.isdigit() or abs(datetime.now(timezone.utc).timestamp() - int(timestamp)) > 300:
            raise ValueError("Stripe signature expirada")
        signed_payload = f"{timestamp}.{payload.decode('utf-8')}"
        expected = hmac.new(
            self.settings.STRIPE_WEBHOOK_SECRET.encode("utf-8"),
            signed_payload.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        if not any(hmac.compare_digest(expected, candidate) for candidate in signatures):
            raise ValueError("Stripe signature invalida")
        return json.loads(payload.decode("utf-8"))

    async def _sync_subscription_record(
        self,
        *,
        tenant_id: str,
        plan: str | None,
        status: str,
        renewal_date: datetime | None,
    ) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _write() -> None:
            current = self.database.fetch_one(
                """
                SELECT plan, monthly_message_limit
                FROM subscriptions
                WHERE tenant_id = %s
                LIMIT 1
                """,
                (tenant_pk,),
            ) or {}
            next_plan = (plan or str(current.get("plan") or "starter")).strip() or "starter"
            next_limit = int(current.get("monthly_message_limit") or 0) or self._default_limit_for_plan(next_plan)
            next_renewal = renewal_date or (datetime.utcnow() + timedelta(days=30))
            self.database.execute(
                """
                UPDATE subscriptions
                SET plan = %s,
                    status = %s,
                    renewal_date = %s,
                    monthly_message_limit = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE tenant_id = %s
                """,
                (next_plan, status, next_renewal, next_limit, tenant_pk),
            )
            self.database.execute(
                """
                UPDATE tenants
                SET plan = %s,
                    status = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                """,
                (next_plan, map_subscription_to_tenant_status(status), tenant_pk),
            )

        await asyncio.to_thread(_write)

    def _default_limit_for_plan(self, plan: str) -> int:
        if plan == "growth":
            return 5000
        if plan == "pro":
            return 20000
        if plan == "enterprise":
            return 100000
        if plan == "on_demand":
            return 0
        return 1000

    async def _upsert_customer_record(
        self,
        *,
        tenant_id: str,
        provider_customer_id: str,
        provider_subscription_id: str | None,
        provider_price_id: str | None,
        status: str,
        current_period_end: datetime | None,
    ) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _write() -> None:
            self.database.execute(
                """
                INSERT INTO billing_customers (
                    tenant_id,
                    provider,
                    provider_customer_id,
                    provider_subscription_id,
                    provider_price_id,
                    status,
                    current_period_end
                ) VALUES (%s, 'stripe', %s, %s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    provider_subscription_id = VALUES(provider_subscription_id),
                    provider_price_id = VALUES(provider_price_id),
                    status = VALUES(status),
                    current_period_end = VALUES(current_period_end),
                    updated_at = CURRENT_TIMESTAMP
                """,
                (
                    tenant_pk,
                    provider_customer_id,
                    provider_subscription_id,
                    provider_price_id,
                    status,
                    current_period_end,
                ),
            )

        await asyncio.to_thread(_write)

    async def _touch_customer_checkout_url(
        self,
        *,
        tenant_id: str,
        provider_customer_id: str,
        checkout_url: str,
    ) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        await self.database.execute_async(
            """
            UPDATE billing_customers
            SET checkout_url = %s, updated_at = CURRENT_TIMESTAMP
            WHERE tenant_id = %s AND provider_customer_id = %s
            """,
            (checkout_url, tenant_pk, provider_customer_id),
        )

    async def _touch_customer_portal_url(
        self,
        *,
        tenant_id: str,
        provider_customer_id: str,
        portal_url: str,
    ) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        await self.database.execute_async(
            """
            UPDATE billing_customers
            SET portal_url = %s, updated_at = CURRENT_TIMESTAMP
            WHERE tenant_id = %s AND provider_customer_id = %s
            """,
            (portal_url, tenant_pk, provider_customer_id),
        )

    async def _upsert_invoice_record(
        self,
        *,
        tenant_id: str,
        provider_invoice_id: str,
        provider_subscription_id: str | None,
        status: str,
        hosted_invoice_url: str | None,
        invoice_pdf_url: str | None,
        amount_due: int,
        amount_paid: int,
        currency: str,
        due_date: datetime | None,
        paid_at: datetime | None,
    ) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _write() -> None:
            self.database.execute(
                """
                INSERT INTO billing_invoices (
                    tenant_id,
                    provider_invoice_id,
                    provider_subscription_id,
                    status,
                    hosted_invoice_url,
                    invoice_pdf_url,
                    amount_due,
                    amount_paid,
                    currency,
                    due_date,
                    paid_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    provider_subscription_id = VALUES(provider_subscription_id),
                    status = VALUES(status),
                    hosted_invoice_url = VALUES(hosted_invoice_url),
                    invoice_pdf_url = VALUES(invoice_pdf_url),
                    amount_due = VALUES(amount_due),
                    amount_paid = VALUES(amount_paid),
                    currency = VALUES(currency),
                    due_date = VALUES(due_date),
                    paid_at = VALUES(paid_at),
                    updated_at = CURRENT_TIMESTAMP
                """,
                (
                    tenant_pk,
                    provider_invoice_id,
                    provider_subscription_id,
                    status,
                    hosted_invoice_url,
                    invoice_pdf_url,
                    amount_due,
                    amount_paid,
                    currency,
                    due_date,
                    paid_at,
                ),
            )

        await asyncio.to_thread(_write)

    async def _find_tenant_id_by_customer(self, customer_id: str) -> str:
        if not customer_id:
            return ""

        def _load() -> str:
            row = self.database.fetch_one(
                """
                SELECT t.external_key AS tenant_id
                FROM billing_customers bc
                INNER JOIN tenants t ON t.id = bc.tenant_id
                WHERE bc.provider_customer_id = %s
                LIMIT 1
                """,
                (customer_id,),
            )
            return str((row or {}).get("tenant_id") or "")

        return await asyncio.to_thread(_load)

    def _map_subscription_status(self, raw_status: str) -> str:
        value = raw_status.strip().lower()
        if value == "active":
            return "active"
        if value == "trialing":
            return "trialing"
        if value in {"past_due", "unpaid", "incomplete"}:
            return "past_due"
        if value in {"canceled", "incomplete_expired"}:
            return "canceled"
        return "inactive"

    def _from_unix(self, raw_value: Any) -> datetime | None:
        if raw_value in (None, "", 0):
            return None
        try:
            return datetime.fromtimestamp(int(raw_value), tz=timezone.utc).replace(tzinfo=None)
        except Exception:
            return None

