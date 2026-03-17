"""Domain models for AI Engine requests and responses"""
from __future__ import annotations

from typing import Any, Dict, List, Literal, Optional, Union

from pydantic import BaseModel, Field, constr


RoleType = Literal["system", "user", "assistant"]


class ChatMessage(BaseModel):
    role: RoleType
    content: constr(strip_whitespace=True, min_length=1)


class AIRequestPayload(BaseModel):
    tenant_id: constr(strip_whitespace=True, min_length=1)
    session_id: Optional[constr(strip_whitespace=True, min_length=1)] = None
    phone_number: Optional[constr(strip_whitespace=True, min_length=1)] = None
    message: Union[Dict[str, Any], str]
    context: List[ChatMessage] = Field(default_factory=list)
    session_state: Dict[str, Any] = Field(default_factory=dict)
    metadata: Optional[Dict[str, Any]] = None

    @property
    def latest_text(self) -> str:
        if isinstance(self.message, dict):
            return str(self.message.get("text", "")).strip()
        return str(self.message).strip()


class AIReply(BaseModel):
    type: Literal["text"] = "text"
    content: str


class AIResponsePayload(BaseModel):
    handled: bool
    reply: AIReply | None = None
    intent: str | None = None
    confidence: float | None = None
    error: str | None = None
    retryable: bool | None = None
    session_state: Dict[str, Any] = Field(default_factory=dict)
    metadata: Dict[str, Any] = Field(default_factory=dict)


class IntentAnalysis(BaseModel):
    intent: str
    confidence: float = 0.0


class PromptSegment(BaseModel):
    role: RoleType
    content: str
