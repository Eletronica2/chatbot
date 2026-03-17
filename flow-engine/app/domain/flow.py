"""Domain models for YAML-based conversational flows"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class FlowValidationError(ValueError):
    """Raised when a flow definition is invalid"""


class FlowOption(BaseModel):
    label: str
    value: str
    metadata: Dict[str, Any] = Field(default_factory=dict)


class FlowTransition(BaseModel):
    condition: str
    target_state: str
    metadata: Dict[str, Any] = Field(default_factory=dict)


class FlowState(BaseModel):
    state: str
    message: Optional[str] = None
    options: List[FlowOption] = Field(default_factory=list)
    transitions: List[FlowTransition] = Field(default_factory=list)
    requires_handoff: bool = False
    hook: Dict[str, Any] = Field(default_factory=dict)


class FlowDefinition(BaseModel):
    name: str
    description: Optional[str] = None
    start_state: str
    states: Dict[str, FlowState]
    metadata: Dict[str, Any] = Field(default_factory=dict)

    def get_state(self, state_name: str) -> Optional[FlowState]:
        return self.states.get(state_name)


class FlowExecuteMessage(BaseModel):
    text: str


class FlowExecutePayload(BaseModel):
    tenant_id: str
    session_id: str
    current_state: Optional[str] = None
    message: FlowExecuteMessage


class FlowExecutionRequest(BaseModel):
    tenant_id: str
    phone_number: Optional[str] = None
    session_id: Optional[str] = None
    message: Dict[str, Any]
    session_state: Dict[str, Any] = Field(default_factory=dict)

    @classmethod
    def from_execute_payload(cls, payload: FlowExecutePayload) -> "FlowExecutionRequest":
        session_state: Dict[str, Any] = {"session_id": payload.session_id}
        if payload.current_state:
            session_state["last_state"] = payload.current_state

        message_payload = {
            "text": payload.message.text,
            "metadata": {
                "source": "flow_api",
                "session_id": payload.session_id,
            },
        }

        return cls(
            tenant_id=payload.tenant_id,
            session_id=payload.session_id,
            message=message_payload,
            session_state=session_state,
        )


class FlowExecutionResponse(BaseModel):
    handled: bool
    reply_text: Optional[str] = None
    session_state: Dict[str, Any] = Field(default_factory=dict)
    metadata: Dict[str, Any] = Field(default_factory=dict)
    requires_handoff: bool = False
