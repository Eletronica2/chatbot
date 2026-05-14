import pytest
from fastapi import HTTPException

from app.api.routes.tenant_settings import (
    TenantSettingsPatchPayload,
    assert_tenant_settings_patch_access,
)
from app.domain.auth import AuthenticatedUser
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


def test_superadmin_can_patch_ai_models():
    user = _authenticated_user('superadmin')
    payload = TenantSettingsPatchPayload(fallback_models=['gemini-2.5-flash'])

    assert_tenant_settings_patch_access(user, payload)

