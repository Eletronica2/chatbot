"""Domain models for tenant subscriptions."""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Literal

from pydantic import BaseModel, Field


SubscriptionStatus = Literal["active", "trialing", "past_due", "canceled", "inactive"]


class TenantSubscription(BaseModel):
    tenant_id: str
    plan: str = "starter"
    status: SubscriptionStatus = "active"
    renewal_date: datetime = Field(
        default_factory=lambda: datetime.utcnow() + timedelta(days=30)
    )
    monthly_message_limit: int = 1000
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    def is_valid(self) -> bool:
        if self.status not in {"active", "trialing"}:
            return False
        return self.renewal_date >= datetime.utcnow()

