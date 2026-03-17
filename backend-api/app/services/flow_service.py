"""Service that integrates with the flow-engine"""
from __future__ import annotations

import logging
from typing import Any, Dict

import httpx

from app.domain.message import FlowExecutionResult, NormalizedMessage
from app.domain.session import ConversationSession

logger = logging.getLogger(__name__)


class FlowService:
    """Executes YAML/JSON flows via the external engine"""

    def __init__(self, base_url: str, timeout: int = 15):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    async def execute_flow(
        self,
        message: NormalizedMessage,
        session: ConversationSession
    ) -> FlowExecutionResult:
        payload: Dict[str, Any] = {
            "tenant_id": message.tenant_id,
            "phone_number": message.phone_number,
            "message": message.model_dump(mode="json"),
            "session_state": session.conversation_state,
        }

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(
                    f"{self.base_url}/flows/execute",
                    json=payload,
                )

            if response.status_code == 200:
                data = response.json()
                logger.info(
                    "Flow engine resolved message %s handled=%s",
                    message.message_id,
                    data.get("handled"),
                )
                return FlowExecutionResult(
                    handled=data.get("handled", False),
                    reply_text=data.get("reply_text"),
                    session_state=data.get("session_state"),
                    metadata=data.get("metadata"),
                    requires_handoff=data.get("requires_handoff", False),
                )

            logger.warning(
                "Flow engine returned non-200 (%s) for message %s",
                response.status_code,
                message.message_id,
            )
            return FlowExecutionResult(
                handled=False,
                metadata={"error": f"flow_engine_status_{response.status_code}"},
            )

        except httpx.RequestError as exc:
            logger.error("Flow engine request failed: %s", exc)
            return FlowExecutionResult(
                handled=False,
                metadata={"error": "flow_engine_unreachable"},
            )
        except Exception as exc:  # pragma: no cover - safeguard
            logger.exception("Unexpected error calling flow engine: %s", exc)
            return FlowExecutionResult(handled=False, metadata={"error": "flow_engine_exception"})

    async def list_admin_flows(self) -> list[dict]:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.get(f"{self.base_url}/flow/admin/flows")
            response.raise_for_status()
            data = response.json()
            return data if isinstance(data, list) else []

    async def get_admin_flow_yaml(self, flow_name: str) -> dict:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.get(f"{self.base_url}/flow/admin/flows/{flow_name}")
            response.raise_for_status()
            data = response.json()
            return data if isinstance(data, dict) else {}

    async def upsert_admin_flow_yaml(self, flow_name: str, yaml_content: str) -> dict:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.put(
                f"{self.base_url}/flow/admin/flows/{flow_name}",
                json={"yaml_content": yaml_content},
            )
            response.raise_for_status()
            data = response.json()
            return data if isinstance(data, dict) else {}

    async def reload_admin_flows(self) -> dict:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(f"{self.base_url}/flow/admin/reload")
            response.raise_for_status()
            data = response.json()
            return data if isinstance(data, dict) else {}
