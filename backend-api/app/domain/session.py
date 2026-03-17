"""Models representing a conversation session"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from pydantic import BaseModel, Field


class ConversationSession(BaseModel):
    """Represents the current state of a conversation"""

    tenant_id: str
    phone_number: str
    conversation_state: Dict[str, Any] = Field(default_factory=dict)
    context: Dict[str, Any] = Field(default_factory=dict)
    last_flow: Optional[str] = None
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    @property
    def key(self) -> str:
        """Unique identifier per tenant/contact"""
        return f"{self.tenant_id}:{self.phone_number}"

    def touch(self) -> None:
        """Refresh update timestamp"""
        self.updated_at = datetime.utcnow()
