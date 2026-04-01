"""Helpers for superadmin and tenant-scoped access."""
from __future__ import annotations

from fastapi import HTTPException, Request

from app.domain.auth import AuthenticatedUser

SUPERADMIN_ROLES = {
    'superadmin',
    'system-admin',
    'system_admin',
    'systemadmin',
}


def is_superadmin(user: AuthenticatedUser) -> bool:
    return str(user.role or '').strip().lower() in SUPERADMIN_ROLES


def resolve_tenant_scope(
    user: AuthenticatedUser,
    request: Request,
    explicit_tenant_id: str | None = None,
) -> str:
    requested_tenant = (
        (explicit_tenant_id or '').strip()
        or str(request.headers.get('x-tenant-id') or '').strip()
        or str(getattr(request.state, 'tenant_id', '') or '').strip()
        or str(user.tenant_id or '').strip()
    )
    if not requested_tenant:
        requested_tenant = str(user.tenant_id or '').strip()

    if is_superadmin(user):
        return requested_tenant

    if requested_tenant != user.tenant_id:
        raise HTTPException(status_code=403, detail='Tenant access denied')
    return user.tenant_id


def assert_tenant_access(user: AuthenticatedUser, tenant_id: str) -> None:
    if is_superadmin(user):
        return
    if user.tenant_id != tenant_id:
        raise HTTPException(status_code=403, detail='Tenant access denied')


def assert_superadmin(user: AuthenticatedUser) -> None:
    if not is_superadmin(user):
        raise HTTPException(status_code=403, detail='Superadmin access required')
