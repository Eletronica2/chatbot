"""Helpers for superadmin, tenant scope and RBAC capabilities."""
from __future__ import annotations

from fastapi import HTTPException, Request

from app.domain.auth import AuthenticatedUser

SUPERADMIN_ROLES = {
    "superadmin",
    "system-admin",
    "system_admin",
    "systemadmin",
}

# Tenant admin = company administrator (owner) + legacy manager with admin powers.
TENANT_ADMIN_ROLES = {
    "owner",
    "manager",
    "admin",
    "tenant_admin",
    "tenant-admin",
}

AGENT_ROLES = {
    "agent",
    "member",
    "atendente",
}


def _role(user: AuthenticatedUser) -> str:
    return str(user.role or "").strip().lower()


def is_superadmin(user: AuthenticatedUser) -> bool:
    return _role(user) in SUPERADMIN_ROLES


def is_tenant_admin(user: AuthenticatedUser) -> bool:
    if is_superadmin(user):
        return True
    return _role(user) in TENANT_ADMIN_ROLES


def is_agent(user: AuthenticatedUser) -> bool:
    if is_superadmin(user) or is_tenant_admin(user):
        return False
    role = _role(user)
    return role in AGENT_ROLES or bool(role)


def resolve_tenant_scope(
    user: AuthenticatedUser,
    request: Request,
    explicit_tenant_id: str | None = None,
) -> str:
    requested_tenant = (
        (explicit_tenant_id or "").strip()
        or str(request.headers.get("x-tenant-id") or "").strip()
        or str(getattr(request.state, "tenant_id", "") or "").strip()
        or str(user.tenant_id or "").strip()
    )
    if not requested_tenant:
        requested_tenant = str(user.tenant_id or "").strip()

    if is_superadmin(user):
        return requested_tenant

    if requested_tenant != user.tenant_id:
        raise HTTPException(status_code=403, detail="Tenant access denied")
    return user.tenant_id


def assert_tenant_access(user: AuthenticatedUser, tenant_id: str) -> None:
    if is_superadmin(user):
        return
    if user.tenant_id != tenant_id:
        raise HTTPException(status_code=403, detail="Tenant access denied")


def assert_superadmin(user: AuthenticatedUser) -> None:
    if not is_superadmin(user):
        raise HTTPException(status_code=403, detail="Superadmin access required")


def assert_tenant_admin(user: AuthenticatedUser) -> None:
    if not is_tenant_admin(user):
        raise HTTPException(status_code=403, detail="Tenant admin access required")


def assert_capability(user: AuthenticatedUser, capability: str) -> None:
    """Raise 403 when the authenticated user lacks a named product capability."""
    if is_superadmin(user):
        return
    caps = capabilities_for(user)
    if not caps.get(capability, False):
        raise HTTPException(status_code=403, detail=f"Missing capability: {capability}")


def capabilities_for(user: AuthenticatedUser) -> dict[str, bool]:
    """Reusable capability map — keep Flutter and backend aligned conceptually."""
    if is_superadmin(user):
        return {
            "canViewConversations": True,
            "canReplyConversations": True,
            "canAssumeConversations": True,
            "canTransferConversations": True,
            "canManageGroups": True,
            "canManageTeam": True,
            "canManageAutomations": True,
            "canManageActions": True,
            "canManageTemplates": True,
            "canManageWhatsApp": True,
            "canManageBilling": True,
            "canManageQuickReplies": True,
            "canViewOverview": True,
            "canAccessBackoffice": True,
        }

    admin = is_tenant_admin(user)
    return {
        "canViewConversations": True,
        "canReplyConversations": True,
        "canAssumeConversations": True,
        "canTransferConversations": True,
        "canManageGroups": admin,
        "canManageTeam": admin,
        "canManageAutomations": admin,
        "canManageActions": admin,
        "canManageTemplates": admin,
        "canManageWhatsApp": admin,
        "canManageBilling": admin,
        "canManageQuickReplies": True,
        "canViewOverview": True,
        "canAccessBackoffice": False,
    }
