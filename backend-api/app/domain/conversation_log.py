"""Domain model for observability logs."""
from __future__ import annotations

from datetime import datetime
from typing import Optional
from uuid import uuid4

from pydantic import BaseModel, Field


class ConversationLog(BaseModel):
    log_id: str = Field(default_factory=lambda: str(uuid4()))
    tenant_id: str
    phone_number: str
    session_id: str
    user_message: str
    bot_response: str
    flow_used: Optional[str] = None
    state: Optional[str] = None
    source: str = "flow"
    detected_intent: Optional[str] = None
    response_time_ms: int = 0
    created_at: datetime = Field(default_factory=datetime.utcnow)

