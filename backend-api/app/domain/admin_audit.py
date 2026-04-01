"""Audit trail models for administrative actions."""
from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel


class AdminAuditEntry(BaseModel):
    audit_id: str
    tenant_id: str
    actor_user_id: str | None = None
    actor_email: str | None = None
    action: str
    entity_type: str
    entity_key: str
    summary: str
    metadata: dict[str, Any] | None = None
    created_at: datetime | None = None
