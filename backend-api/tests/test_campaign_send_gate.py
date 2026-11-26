"""Campaign send gate messages."""
from __future__ import annotations

from datetime import datetime, timedelta
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.services.subscription_service import SubscriptionCheck
from app.services.whatsapp_campaign_service import WhatsAppCampaignService
from app.domain.subscription import TenantSubscription


@pytest.mark.asyncio
async def test_sends_blocked_past_due_message(monkeypatch):
    from app.config import settings as settings_mod

    monkeypatch.setattr(settings_mod.settings, "CAMPAIGN_SEND_ENABLED", True)
    svc = WhatsAppCampaignService(MagicMock(), MagicMock(), MagicMock(), subscription_service=MagicMock())
    sub = TenantSubscription(
        tenant_id="t1",
        plan="starter",
        status="past_due",
        renewal_date=datetime.utcnow() + timedelta(days=5),
        monthly_message_limit=1000,
    )
    check = SubscriptionCheck(False, "subscription_inactive", sub, 0)
    svc.subscription_service.check_message_allowance = AsyncMock(return_value=check)
    allowed, code, message, snapshot = await svc._sends_allowed("t1")
    assert not allowed
    assert code == "subscription_inactive"
    assert snapshot is not None
    assert snapshot.status == "past_due"
    assert "past_due" in (message or "").lower()