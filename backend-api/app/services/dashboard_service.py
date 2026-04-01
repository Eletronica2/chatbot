"""Aggregated dashboard metrics for superadmin and tenant views."""
from __future__ import annotations

import asyncio
from datetime import datetime

from app.api.access import is_superadmin
from app.config.settings import Settings
from app.db.mysql import MySQLDatabase
from app.domain.auth import AuthenticatedUser
from app.domain.dashboard_metrics import (
    DashboardKpi,
    DashboardOverview,
    DashboardPlanBreakdown,
    DashboardRecentEvent,
    DashboardTopTenant,
)
from app.services.billing_service import BillingService
from app.services.flow_service import FlowService
from app.services.subscription_service import SubscriptionService


class DashboardService:
    def __init__(
        self,
        *,
        database: MySQLDatabase,
        subscription_service: SubscriptionService,
        billing_service: BillingService,
        settings: Settings,
        flow_service: FlowService | None = None,
    ):
        self.database = database
        self.subscription_service = subscription_service
        self.billing_service = billing_service
        self.settings = settings
        self.flow_service = flow_service

    async def build_overview(
        self,
        *,
        user: AuthenticatedUser,
        requested_tenant_id: str,
    ) -> DashboardOverview:
        if is_superadmin(user) and requested_tenant_id == self.settings.DEFAULT_TENANT_ID:
            return await self._build_global_overview()
        return await self._build_tenant_overview(requested_tenant_id)

    async def _build_global_overview(self) -> DashboardOverview:
        now = datetime.utcnow()
        month_start = datetime(now.year, now.month, 1)

        def _load() -> DashboardOverview:
            totals = self.database.fetch_one(
                """
                SELECT
                    COUNT(*) AS tenant_count,
                    SUM(CASE WHEN s.status IN ('active', 'trialing') THEN 1 ELSE 0 END) AS active_count,
                    SUM(CASE WHEN s.status = 'past_due' THEN 1 ELSE 0 END) AS past_due_count,
                    SUM(CASE WHEN s.status = 'canceled' THEN 1 ELSE 0 END) AS canceled_count
                FROM tenants t
                LEFT JOIN subscriptions s ON s.tenant_id = t.id
                WHERE t.external_key <> %s
                """,
                (self.settings.DEFAULT_TENANT_ID,),
            ) or {}

            usage = self.database.fetch_one(
                """
                SELECT COUNT(*) AS message_count
                FROM messages m
                INNER JOIN tenants t ON t.id = m.tenant_id
                WHERE t.external_key <> %s
                  AND m.direction = 'incoming'
                  AND m.created_at >= %s
                """,
                (self.settings.DEFAULT_TENANT_ID, month_start),
            ) or {}

            plan_rows = self.database.fetch_all(
                """
                SELECT s.plan, COUNT(*) AS tenant_count
                FROM subscriptions s
                INNER JOIN tenants t ON t.id = s.tenant_id
                WHERE t.external_key <> %s
                GROUP BY s.plan
                ORDER BY tenant_count DESC, s.plan ASC
                """,
                (self.settings.DEFAULT_TENANT_ID,),
            )

            top_rows = self.database.fetch_all(
                """
                SELECT
                    t.external_key AS tenant_id,
                    t.name AS tenant_name,
                    COALESCE(s.plan, 'starter') AS plan,
                    COALESCE(s.status, 'inactive') AS status,
                    COALESCE(s.monthly_message_limit, 0) AS monthly_message_limit,
                    COUNT(m.id) AS used_messages
                FROM tenants t
                LEFT JOIN subscriptions s ON s.tenant_id = t.id
                LEFT JOIN messages m
                    ON m.tenant_id = t.id
                   AND m.direction = 'incoming'
                   AND m.created_at >= %s
                WHERE t.external_key <> %s
                GROUP BY t.id, t.external_key, t.name, s.plan, s.status, s.monthly_message_limit
                ORDER BY used_messages DESC, t.name ASC
                LIMIT 6
                """,
                (month_start, self.settings.DEFAULT_TENANT_ID),
            )

            event_rows = self.database.fetch_all(
                """
                SELECT aal.action, aal.summary, aal.actor_email, aal.created_at, t.external_key AS tenant_id
                FROM admin_audit_logs aal
                INNER JOIN tenants t ON t.id = aal.tenant_id
                WHERE t.external_key <> %s
                ORDER BY aal.created_at DESC
                LIMIT 10
                """,
                (self.settings.DEFAULT_TENANT_ID,),
            )

            plan_breakdown: list[DashboardPlanBreakdown] = []
            estimated_mrr = 0
            for row in plan_rows:
                plan = str(row.get("plan") or "starter")
                count = int(row.get("tenant_count") or 0)
                mrr = self.billing_service.estimate_plan_mrr_cents(plan) * count
                estimated_mrr += mrr
                plan_breakdown.append(
                    DashboardPlanBreakdown(
                        plan=plan,
                        tenants=count,
                        estimated_mrr_cents=mrr,
                    )
                )

            kpis = [
                DashboardKpi(
                    label="Tenants ativos",
                    value=str(int(totals.get("active_count") or 0)),
                    helper=f"{int(totals.get('tenant_count') or 0)} clientes no total",
                    tone="success",
                ),
                DashboardKpi(
                    label="Mensagens do mes",
                    value=str(int(usage.get("message_count") or 0)),
                    helper="Entradas recebidas no periodo atual",
                    tone="default",
                ),
                DashboardKpi(
                    label="Planos em atraso",
                    value=str(int(totals.get("past_due_count") or 0)),
                    helper="Tenants com risco de bloqueio",
                    tone="danger",
                ),
                DashboardKpi(
                    label="MRR estimado",
                    value=self._format_money(estimated_mrr),
                    helper="Baseado no catalogo interno de planos",
                    tone="accent",
                ),
            ]

            return DashboardOverview(
                scope="global",
                tenant_id=self.settings.DEFAULT_TENANT_ID,
                tenant_name="Operacao SaaS",
                kpis=kpis,
                plan_breakdown=plan_breakdown,
                top_tenants=[
                    DashboardTopTenant(
                        tenant_id=str(row.get("tenant_id") or ""),
                        tenant_name=str(row.get("tenant_name") or ""),
                        plan=str(row.get("plan") or "starter"),
                        status=str(row.get("status") or "inactive"),
                        used_messages=int(row.get("used_messages") or 0),
                        monthly_message_limit=int(row.get("monthly_message_limit") or 0),
                    )
                    for row in top_rows
                ],
                recent_events=[
                    DashboardRecentEvent(
                        action=str(row.get("action") or ""),
                        summary=str(row.get("summary") or ""),
                        tenant_id=str(row.get("tenant_id") or ""),
                        actor_email=row.get("actor_email"),
                        created_at=row.get("created_at"),
                    )
                    for row in event_rows
                ],
            )

        return await asyncio.to_thread(_load)

    async def _build_tenant_overview(self, tenant_id: str) -> DashboardOverview:
        usage = await self.subscription_service.get_usage_snapshot(tenant_id)
        subscription = await self.subscription_service.get_or_create(tenant_id)
        tenant_row = self.database.get_tenant_record(tenant_id) or {}
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        flow_count = await self._count_flows_for_tenant(tenant_id, tenant_pk)

        def _load() -> DashboardOverview:
            account_row = self.database.fetch_one(
                """
                SELECT COUNT(*) AS total
                FROM whatsapp_accounts
                WHERE tenant_id = %s AND status = 'active'
                """,
                (tenant_pk,),
            ) or {}
            conv_row = self.database.fetch_one(
                """
                SELECT COUNT(*) AS total
                FROM sessions
                WHERE tenant_id = %s
                """,
                (tenant_pk,),
            ) or {}
            recent_rows = self.database.fetch_all(
                """
                SELECT action, summary, actor_email, created_at
                FROM admin_audit_logs
                WHERE tenant_id = %s
                ORDER BY created_at DESC
                LIMIT 8
                """,
                (tenant_pk,),
            )

            kpis = [
                DashboardKpi(
                    label="Plano atual",
                    value=subscription.plan,
                    helper=f"Renova em {subscription.renewal_date.strftime('%d/%m/%Y')}",
                    tone="accent",
                ),
                DashboardKpi(
                    label="Mensagens usadas",
                    value=str(int(usage.get("used_messages") or 0)),
                    helper=f"de {int(usage.get('monthly_message_limit') or 0)} no mes",
                    tone="default",
                ),
                DashboardKpi(
                    label="Fluxos ativos",
                    value=str(flow_count),
                    helper="Fluxos disponiveis no builder",
                    tone="success",
                ),
                DashboardKpi(
                    label="Contas WhatsApp",
                    value=str(int(account_row.get("total") or 0)),
                    helper=f"{int(conv_row.get('total') or 0)} conversas registradas",
                    tone="default",
                ),
            ]

            return DashboardOverview(
                scope="tenant",
                tenant_id=tenant_id,
                tenant_name=str(tenant_row.get("name") or tenant_id),
                kpis=kpis,
                plan_breakdown=[
                    DashboardPlanBreakdown(
                        plan=subscription.plan,
                        tenants=1,
                        estimated_mrr_cents=self.billing_service.estimate_plan_mrr_cents(subscription.plan),
                    )
                ],
                recent_events=[
                    DashboardRecentEvent(
                        action=str(row.get("action") or ""),
                        summary=str(row.get("summary") or ""),
                        tenant_id=tenant_id,
                        actor_email=row.get("actor_email"),
                        created_at=row.get("created_at"),
                    )
                    for row in recent_rows
                ],
            )

        return await asyncio.to_thread(_load)

    async def _count_flows_for_tenant(self, tenant_id: str, tenant_pk: int) -> int:
        if self.flow_service is not None:
            try:
                flows = await self.flow_service.list_admin_flows(tenant_id=tenant_id)
                return len(flows)
            except Exception:
                pass

        def _fallback() -> int:
            row = self.database.fetch_one(
                "SELECT COUNT(*) AS total FROM flows WHERE tenant_id = %s",
                (tenant_pk,),
            ) or {}
            return int(row.get("total") or 0)

        return await asyncio.to_thread(_fallback)

    def _format_money(self, cents: int) -> str:
        value = cents / 100
        return f"R$ {value:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
