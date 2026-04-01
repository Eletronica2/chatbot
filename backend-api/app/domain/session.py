"""Domain models representing a conversation session."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional
from uuid import uuid4

from pydantic import BaseModel, Field


class SessionMessage(BaseModel):
    role: str
    content: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


class ConversationSession(BaseModel):
    """Represents the current state of a conversation."""

    session_id: str = Field(default_factory=lambda: str(uuid4()))
    tenant_id: str
    phone_number: str
    phone_number_id: Optional[str] = None
    display_phone_number: Optional[str] = None
    active_flow: Optional[str] = None
    current_state: Optional[str] = None
    detected_intent: Optional[str] = None
    conversation_history: List[SessionMessage] = Field(default_factory=list)
    last_interaction: datetime = Field(default_factory=datetime.utcnow)
    conversation_state: Dict[str, Any] = Field(default_factory=dict)
    context: Dict[str, Any] = Field(default_factory=dict)
    last_flow: Optional[str] = None
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    @property
    def key(self) -> str:
        return f"{self.tenant_id}:{self.phone_number}"

    def append_history(self, role: str, content: str, limit: int = 10) -> None:
        if not content:
            return
        self.conversation_history.append(SessionMessage(role=role, content=content))
        if limit > 0:
            self.conversation_history = self.conversation_history[-limit:]
        self.last_interaction = datetime.utcnow()

    def touch(self) -> None:
        self.updated_at = datetime.utcnow()
        self.last_interaction = datetime.utcnow()

