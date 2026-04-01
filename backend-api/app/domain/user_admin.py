"""Domain models for tenant user administration."""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class TenantUser(BaseModel):
    user_id: str
    tenant_id: str
    email: str
    display_name: str
    role: str = "owner"
    status: str = "active"
    created_at: datetime | None = None
    last_login_at: datetime | None = None


class TenantUserActionToken(BaseModel):
    token_type: str
    token: str
    expires_at: datetime
    action_url: str
    user: TenantUser
    email_status: str | None = None
    email_error: str | None = None
