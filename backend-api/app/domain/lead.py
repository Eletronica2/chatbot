"""Domain models for landing-page lead capture."""
from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel


class Lead(BaseModel):
    id: str
    name: str
    company: str
    segment: str | None = None
    email: str
    whatsapp: str
    objective: str
    monthly_volume: str | None = None
    team_size: str | None = None
    current_tools: str | None = None
    best_contact_time: str | None = None
    source: str = "landing"
    status: str = "new"
    notes: str | None = None
    assigned_to: str | None = None
    metadata: dict[str, Any] | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
