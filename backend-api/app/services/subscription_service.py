"""Persistent subscription service used to gate message processing."""
from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional

from app.config.settings import Settings
from app.db.mysql import MySQLDatabase
from app.domain.subscription import TenantSubscription, map_subscription_to_tenant_status
from app.repositories.message_repository import MessageRepository


@dataclass(slots=True)
class SubscriptionCheck:
    allowed: bool
    reason: str | None
    subscription: TenantSubscription
    used_messages: int


_PLAN_LIMITS = {
    "starter": 1000,
    "growth": 5000,
    "pro": 20000,
    "enterprise": 100000,
}


class SubscriptionService:
    def __init__(
        self,
        database: MySQLDatabase,
        message_repository: MessageRepository,
        settings: Settings,
    ):
        self.database = database
        self.message_repository = message_repository
        self.settings = settings

    async def get_or_create(self, tenant_id: str) -> TenantSubscription:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _load() -> TenantSubscription:
            row = self.database.fetch_one(
                """
                SELECT plan, status, renewal_date, monthly_message_limit, created_at, updated_at
                FROM subscriptions
                WHERE tenant_id = %s
                LIMIT 1
                """,
                (tenant_pk,),
            )
            if row is None:
                renewal_date = datetime.utcnow() + timedelta(days=30)
                self.database.execute(
                    """
                    INSERT INTO subscriptions (tenant_id, plan, status, renewal_date, monthly_message_limit)
                    VALUES (%s, 'starter', 'active', %s, %s)
                    """,
                    (tenant_pk, renewal_date, _PLAN_LIMITS["starter"]),
                )
                row = self.database.fetch_one(
                    """
                    SELECT plan, status, renewal_date, monthly_message_limit, created_at, updated_at
                    FROM subscriptions
                    WHERE tenant_id = %s
                    LIMIT 1
                    """,
                    (tenant_pk,),
                ) or {}
            return TenantSubscription(
                tenant_id=tenant_id,
                plan=str(row.get("plan") or "starter"),
                status=str(row.get("status") or "active"),
                renewal_date=row.get("renewal_date") or (datetime.utcnow() + timedelta(days=30)),
                monthly_message_limit=int(row.get("monthly_message_limit") or _PLAN_LIMITS["starter"]),
                created_at=row.get("created_at") or datetime.utcnow(),
                updated_at=row.get("updated_at") or datetime.utcnow(),
            )

        return await asyncio.to_thread(_load)

    async def update(
        self,
        tenant_id: str,
        *,
        plan: Optional[str] = None,
        status: Optional[str] = None,
        renewal_date: Optional[datetime] = None,
        monthly_message_limit: Optional[int] = None,
    ) -> TenantSubscription:
        current = await self.get_or_create(tenant_id)
        next_plan = plan.strip() if isinstance(plan, str) and plan.strip() else current.plan
        next_status = status.strip() if isinstance(status, str) and status.strip() else current.status
        next_renewal = renewal_date or current.renewal_date
        next_limit = monthly_message_limit if monthly_message_limit is not None else _PLAN_LIMITS.get(next_plan, current.monthly_message_limit)
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        await asyncio.to_thread(
            self._update_subscription_record,
            tenant_pk,
            next_plan,
            next_status,
            next_renewal,
            next_limit,
        )
        return await self.get_or_create(tenant_id)

    async def is_active(self, tenant_id: str) -> bool:
        subscription = await self.get_or_create(tenant_id)
        subscription = await self._apply_renewal_guard(tenant_id, subscription)
        return subscription.is_valid()

    async def check_message_allowance(self, tenant_id: str) -> SubscriptionCheck:
        subscription = await self.get_or_create(tenant_id)
        subscription = await self._apply_renewal_guard(tenant_id, subscription)
        if not subscription.is_valid():
            used = await self._count_usage(tenant_id)
            return SubscriptionCheck(False, "subscription_inactive", subscription, used)

        used_messages = await self._count_usage(tenant_id)
        if subscription.monthly_message_limit > 0 and used_messages >= subscription.monthly_message_limit:
            return SubscriptionCheck(False, "message_limit_reached", subscription, used_messages)
        return SubscriptionCheck(True, None, subscription, used_messages)

    async def get_usage_snapshot(self, tenant_id: str) -> dict[str, int | str]:
        subscription = await self.get_or_create(tenant_id)
        used = await self._count_usage(tenant_id)
        remaining = max(subscription.monthly_message_limit - used, 0)
        return {
            "plan": subscription.plan,
            "status": subscription.status,
            "monthly_message_limit": subscription.monthly_message_limit,
            "used_messages": used,
            "remaining_messages": remaining,
        }

    async def _apply_renewal_guard(
        self,
        tenant_id: str,
        subscription: TenantSubscription,
    ) -> TenantSubscription:
        if subscription.status not in {"active", "trialing"}:
            return subscription
        grace_days = max(self.settings.BILLING_GRACE_DAYS, 0)
        grace_limit = subscription.renewal_date + timedelta(days=grace_days)
        if grace_limit >= datetime.utcnow():
            return subscription
        return await self.update(
            tenant_id,
            status="past_due",
            renewal_date=subscription.renewal_date,
            plan=subscription.plan,
            monthly_message_limit=subscription.monthly_message_limit,
        )

    async def _count_usage(self, tenant_id: str) -> int:
        now = datetime.utcnow()
        period_start = datetime(now.year, now.month, 1)
        return await self.message_repository.count_incoming_since(
            tenant_id=tenant_id,
            since=period_start,
        )

    def _update_subscription_record(
        self,
        tenant_pk: int,
        plan: str,
        status: str,
        renewal_date: datetime,
        monthly_message_limit: int,
    ) -> None:
        with self.database.transaction() as conn:
            with conn.cursor() as cursor:
                cursor.execute(
                    """
                    UPDATE subscriptions
                    SET plan = %s,
                        status = %s,
                        renewal_date = %s,
                        monthly_message_limit = %s,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE tenant_id = %s
                    """,
                    (plan, status, renewal_date, monthly_message_limit, tenant_pk),
                )
                cursor.execute(
                    """
                    UPDATE tenants
                    SET plan = %s,
                        status = %s,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = %s
                    """,
                    (plan, map_subscription_to_tenant_status(status), tenant_pk),
                )

