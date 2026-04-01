"""Authentication models used by the admin panel."""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class AuthenticatedUser(BaseModel):
    user_id: str
    tenant_id: str
    email: str
    display_name: str
    role: str = "owner"
    status: str = "active"
    created_at: datetime | None = None
    last_login_at: datetime | None = None


class AuthTokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int = Field(default=43200)
    user: AuthenticatedUser

