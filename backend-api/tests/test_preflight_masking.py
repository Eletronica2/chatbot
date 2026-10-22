from types import SimpleNamespace

from app.api.routes.whatsapp_onboarding import mask_preflight_for

PREFLIGHT = {"app_id": "873826165763092", "config_id": "cfg", "verify_token": "real-platform-token-value",
             "meta_links": {"whatsapp_webhook": "https://example.invalid"}}


def test_tenant_users_never_receive_the_verify_token():
    for role in ("owner", "manager", "agent"):
        data = mask_preflight_for(SimpleNamespace(role=role), dict(PREFLIGHT))
        assert data["verify_token"] == "••••••••" and data["verify_token_configured"] is True
        assert "real-platform-token-value" not in str(data)
        assert data["config_id"] == "cfg" and data["meta_links"] == PREFLIGHT["meta_links"]


def test_superadmin_keeps_the_value_for_webhook_setup():
    data = mask_preflight_for(SimpleNamespace(role="superadmin"), dict(PREFLIGHT))
    assert data["verify_token"] == "real-platform-token-value"


def test_unconfigured_token_is_reported_as_empty():
    data = mask_preflight_for(SimpleNamespace(role="owner"), {**PREFLIGHT, "verify_token": ""})
    assert data["verify_token"] == "" and data["verify_token_configured"] is False
