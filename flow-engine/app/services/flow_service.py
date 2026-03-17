"""High-level service orchestrating flow selection and execution"""
from __future__ import annotations

from typing import Dict, Optional

from app.domain.flow import FlowDefinition, FlowExecutionRequest, FlowExecutionResponse
from app.services.flow_loader import FlowLoader
from app.services.flow_runner import FlowRunner


class FlowService:
    """Exposes a simple API used by the FastAPI layer"""

    def __init__(self, loader: FlowLoader, runner: FlowRunner, default_flow: str):
        self.loader = loader
        self.runner = runner
        self.default_flow = default_flow

    def reload(self) -> Dict[str, FlowDefinition]:
        return self.loader.load_flows()

    async def execute_flow(self, request: FlowExecutionRequest) -> FlowExecutionResponse:
        flow = self._select_flow(request)
        if not flow:
            return FlowExecutionResponse(
                handled=False,
                metadata={"error": "flow_not_found"},
                session_state=request.session_state,
            )
        return await self.runner.run(flow, request)

    def _select_flow(self, request: FlowExecutionRequest) -> Optional[FlowDefinition]:
        candidate_name = self._explicit_flow(request) or self._session_flow(request)
        if candidate_name:
            flow = self.loader.get_flow(candidate_name)
            if flow:
                return flow
        return self.loader.get_flow(self.default_flow)

    def _explicit_flow(self, request: FlowExecutionRequest) -> Optional[str]:
        message = request.message or {}
        if not isinstance(message, dict):
            return None
        for key in ("flow", "flow_name"):
            value = message.get(key)
            if isinstance(value, str):
                return value
        metadata = message.get("metadata")
        if isinstance(metadata, dict):
            value = metadata.get("flow") or metadata.get("flow_name")
            if isinstance(value, str):
                return value
        return None

    def _session_flow(self, request: FlowExecutionRequest) -> Optional[str]:
        session_state = request.session_state or {}
        for key in ("active_flow", "last_flow"):
            value = session_state.get(key)
            if isinstance(value, str):
                return value
        return None

    def list_flows(self) -> Dict[str, FlowDefinition]:
        return self.loader.list_flows()
