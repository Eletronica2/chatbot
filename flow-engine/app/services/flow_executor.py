"""Executes flows based on incoming requests"""
from __future__ import annotations

import logging
from typing import Dict, Optional

from app.domain.flow import (
    FlowDefinition,
    FlowExecutionRequest,
    FlowExecutionResponse,
    FlowState,
)
from app.services.flow_loader import FlowLoader

logger = logging.getLogger(__name__)


class FlowExecutor:
    """Very simple rule-based executor that walks nodes sequentially"""

    def __init__(self, loader: FlowLoader, default_flow: str):
        self.loader = loader
        self.default_flow = default_flow

    async def execute(self, request: FlowExecutionRequest) -> FlowExecutionResponse:
        flow = self._select_flow(request)
        if not flow:
            logger.warning("Requested flow not found; returning unhandled")
            return FlowExecutionResponse(
                handled=False,
                metadata={"error": "flow_not_found"},
            )

        state = flow.get_state(flow.start_state)
        if not state:
            return FlowExecutionResponse(
                handled=False,
                metadata={"error": "invalid_flow_start"},
            )

        reply_text = state.message or ""
        session_state = request.session_state.copy()
        session_state["last_flow"] = flow.name
        session_state["last_state"] = state.state

        logger.debug(
            "Flow %s handled message for tenant %s",
            flow.name,
            request.tenant_id,
        )

        return FlowExecutionResponse(
            handled=bool(reply_text),
            reply_text=reply_text,
            session_state=session_state,
            metadata={"flow": flow.name, "state": state.state},
        )

    def _select_flow(self, request: FlowExecutionRequest) -> Optional[FlowDefinition]:
        # Placeholder strategy: use session state's last_flow, fallback to default
        session_flow = request.session_state.get("last_flow") if request.session_state else None
        if session_flow:
            flow = self.loader.get_flow(session_flow)
            if flow:
                return flow
        return self.loader.get_flow(self.default_flow)
