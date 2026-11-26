import inspect

import pytest
from fastapi import HTTPException

from app.services.tenant_admin_service import TenantAdminService

from app.api.routes.tenant_settings import (
    TenantSettingsPatchPayload,
    assert_tenant_settings_patch_access,
)
from app.domain.auth import AuthenticatedUser
from app.api.routes.whatsapp_onboarding import EmbeddedSignupExchangePayload
from app.services.whatsapp_onboarding_service import resolve_signup_display_fields
from app.domain.subscription import map_subscription_to_tenant_status
from app.domain.tenant import normalize_model_list
from app.security.jwt_tools import hash_password, verify_password


def _authenticated_user(role: str) -> AuthenticatedUser:
    return AuthenticatedUser(
        user_id='user-1',
        tenant_id='tenant-demo',
        email='user@example.com',
        display_name='User Demo',
        role=role,
    )


def test_bootstrap_tenant_keeps_copy_default_flows_optional():
    params = inspect.signature(TenantAdminService.ensure_bootstrap_tenant).parameters
    assert 'copy_default_flows' in params
    assert params['copy_default_flows'].default is True


def test_hash_password_roundtrip():
    encoded = hash_password('senha-super-segura')
    assert encoded.startswith('pbkdf2_sha256$')
    assert verify_password('senha-super-segura', encoded) is True
    assert verify_password('senha-errada', encoded) is False


def test_normalize_model_list_removes_duplicates_and_prefixes():
    models = normalize_model_list([
        'models/gemini-2.0-flash',
        ' gemini-2.0-flash ',
        'gemini-1.5-pro-latest',
        '',
    ])
    assert models == ['gemini-2.0-flash', 'gemini-1.5-pro-latest']


def test_map_subscription_to_tenant_status_uses_valid_lifecycle_values():
    assert map_subscription_to_tenant_status('active') == 'active'
    assert map_subscription_to_tenant_status('trialing') == 'active'
    assert map_subscription_to_tenant_status('inactive') == 'inactive'
    assert map_subscription_to_tenant_status('past_due') == 'suspended'
    assert map_subscription_to_tenant_status('canceled') == 'suspended'


def test_company_admin_cannot_patch_ai_models():
    user = _authenticated_user('owner')
    payload = TenantSettingsPatchPayload(gemini_model='gemini-2.0-flash')

    with pytest.raises(HTTPException) as err:
        assert_tenant_settings_patch_access(user, payload)

    assert err.value.status_code == 403
    assert err.value.detail == 'Superadmin access required'


def test_company_admin_can_patch_non_model_settings():
    user = _authenticated_user('owner')
    payload = TenantSettingsPatchPayload(ai_enabled=False, debug_mode=True)

    assert_tenant_settings_patch_access(user, payload)


def test_company_admin_cannot_select_local_provider():
    user = _authenticated_user('owner')
    payload = TenantSettingsPatchPayload(ai_provider='local', local_ai_enabled=True)
    with pytest.raises(HTTPException) as err:
        assert_tenant_settings_patch_access(user, payload)
    assert err.value.status_code == 403


def test_tenant_ai_metadata_cannot_be_spoofed_and_local_is_opt_in():
    from app.domain.tenant import TenantSettings

    default = TenantSettings(tenant_id='tenant-demo')
    assert default.as_ai_metadata()['ai_provider'] == 'gemini'
    local = TenantSettings(tenant_id='tenant-demo', ai_provider='local', local_ai_enabled=True)
    assert local.as_ai_metadata()['ai_provider'] == 'local'
    disabled = TenantSettings(tenant_id='tenant-demo', ai_provider='local', local_ai_enabled=False)
    assert disabled.as_ai_metadata()['ai_provider'] == 'gemini'


def test_embedded_signup_exchange_accepts_empty_display_phone():
    payload = EmbeddedSignupExchangePayload(
        code='oauth-code',
        waba_id='123456789012345',
        phone_number_id='109876543210987',
        display_phone_number='',
        display_name='',
    )
    assert payload.display_phone_number == '109876543210987'
    assert payload.display_name == 'WhatsApp 109876543210987'


def test_embedded_signup_exchange_accepts_v5_messaging_account_ids():
    payload = EmbeddedSignupExchangePayload(
        code='oauth-code',
        messaging_account_ids=['555000111222333'],
        phone_number_id='109876543210987',
    )
    assert payload.messaging_account_ids == ['555000111222333']
    assert payload.waba_id == ''


def test_resolve_signup_display_fields_prefers_graph_phone():
    phone, name = resolve_signup_display_fields(
        phone_number_id='1155710810954749',
        display_phone_number='1155710810954749',
        display_name='WhatsApp 1155710810954749',
        phone_status={
            'display_phone_number': '+55 34 3195-3594',
            'verified_name': 'Atende Ai',
        },
    )
    assert phone == '+55 34 3195-3594'
    assert name == 'Atende Ai'


def test_build_business_setup_omits_empty_and_blocks_atende_portfolio():
    from app.services.whatsapp_onboarding_service import build_business_setup, resolve_messaging_account_id

    assert build_business_setup(tenant_name='', tenant_email='') == {}
    filled = build_business_setup(
        tenant_name='Loja Demo',
        tenant_email='loja@example.com',
        website='https://loja.example.com',
        country='BR',
        timezone='UTC-03:00',
    )
    assert filled == {
        'name': 'Loja Demo',
        'email': 'loja@example.com',
        'website': 'https://loja.example.com',
        'timezone': 'UTC-03:00',
        'address': {'country': 'BR'},
    }
    blocked = build_business_setup(business_portfolio_id='506485032393364', tenant_name='X')
    assert 'id' not in blocked
    assert blocked.get('name') == 'X'
    assert build_business_setup(business_portfolio_id='999888777666555') == {'id': '999888777666555'}
    assert resolve_messaging_account_id(messaging_account_ids=['111', '222']) == '111'
    assert resolve_messaging_account_id(waba_id='333') == '333'


def test_superadmin_can_patch_ai_models():
    user = _authenticated_user('superadmin')
    payload = TenantSettingsPatchPayload(fallback_models=['gemini-2.5-flash'])

    assert_tenant_settings_patch_access(user, payload)

