"""Campaign authorization gates (no MySQL)."""
from __future__ import annotations

import pytest
from unittest.mock import AsyncMock, MagicMock

from app.services.whatsapp_campaign_service import WhatsAppCampaignService


@pytest.mark.asyncio
async def test_start_campaign_requires_explicit_confirm():
    svc = WhatsAppCampaignService(
        MagicMock(),
        MagicMock(),
        MagicMock(),
    )
    svc._require_campaign = AsyncMock(return_value={"id": 1, "status": "validated"})
    with pytest.raises(ValueError, match="Confirmação"):
        await svc.start_campaign("t1", "c1", confirm=False)


@pytest.mark.asyncio
async def test_charge_meta_false_skips_billing(monkeypatch):
    """Campaign sends pass billing_enforced=False to gateway only."""
    from app.services import whatsapp_template_service as mod
    import httpx

    captured: dict = {}

    class _Resp:
        status_code = 200

        def json(self):
            return {"message_id": "wamid.test"}

        text = ""

    async def _post(*_a, **kw):
        captured.update(kw.get("json") or {})
        return _Resp()

    svc = mod.WhatsAppTemplateService(MagicMock(), MagicMock())
    svc._access_token = AsyncMock(return_value=("k", "tok", False))
    svc._normalize_phone = lambda v: "5534999999999"
    svc.whatsapp_account_service.list_accounts = AsyncMock(
        return_value=[MagicMock(account_key="k", phone_number_id="pn")]
    )
    from types import SimpleNamespace

    svc.list_templates = AsyncMock(
        return_value=[
            SimpleNamespace(
                name="tpl",
                language="pt_BR",
                status="APPROVED",
                category="UTILITY",
                body_text="oi",
            )
        ]
    )

    monkeypatch.setattr(httpx.AsyncClient, "post", _post)
    monkeypatch.setattr(mod.settings, "GATEWAY_API_URL", "http://gw")
    monkeypatch.setattr(mod.settings, "INTERNAL_API_KEY", "k")

    await svc.send_production_template(
        tenant_id="t",
        account_key="k",
        template_name="tpl",
        language="pt_BR",
        to="5534999999999",
        body_parameters=[],
        charge_meta=False,
    )
    assert captured.get("billing_enforced") is False
    assert "billing_reservation_id" not in captured