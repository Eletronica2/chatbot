"""Core conversational flow runner"""
from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from app.domain.flow import FlowDefinition, FlowExecutionRequest, FlowExecutionResponse, FlowState


class FlowRunner:
    """Evaluates flow transitions and produces structured responses"""

    async def run(
        self,
        definition: FlowDefinition,
        request: FlowExecutionRequest,
    ) -> FlowExecutionResponse:
        session_state = dict(request.session_state or {})

        current_state_name = session_state.get("last_state") or definition.start_state
        current_state = definition.get_state(current_state_name)
        if not current_state:
            return FlowExecutionResponse(
                handled=False,
                session_state=session_state,
                metadata={
                    "flow": definition.name,
                    "state": current_state_name,
                    "error": "state_not_found",
                },
            )

        is_first_visit = "last_state" not in session_state
        if is_first_visit:
            return self._build_response(definition, current_state, session_state)

        next_state = self._resolve_transition(current_state, definition, request)
        if not next_state:
            return FlowExecutionResponse(
                handled=False,
                session_state=session_state,
                metadata={
                    "flow": definition.name,
                    "state": current_state.state,
                    "error": "no_transition_match",
                },
            )

        return self._build_response(definition, next_state, session_state)

    def _build_response(
        self,
        definition: FlowDefinition,
        state: FlowState,
        session_state: Dict[str, Any],
    ) -> FlowExecutionResponse:
        session_state = dict(session_state)
        session_state["last_state"] = state.state
        session_state["last_flow"] = definition.name
        session_state["active_flow"] = definition.name

        options = [option.model_dump() for option in state.options]

        return FlowExecutionResponse(
            handled=bool((state.message or "").strip() or options),
            reply_text=state.message,
            session_state=session_state,
            metadata={
                "flow": definition.name,
                "state": state.state,
                "options": options,
                "hook": state.hook,
            },
            requires_handoff=state.requires_handoff,
        )

    def _resolve_transition(
        self,
        state: FlowState,
        definition: FlowDefinition,
        request: FlowExecutionRequest,
    ) -> Optional[FlowState]:
        if not state.transitions:
            return None

        text_candidates = self._extract_text_candidates(request.message)
        for transition in state.transitions:
            if self._condition_matches(transition.condition, text_candidates, request.session_state):
                next_state = definition.get_state(transition.target_state)
                if next_state:
                    return next_state
        return None

    def _extract_text_candidates(self, message: Dict[str, Any]) -> List[str]:
        candidates: List[str] = []
        if not isinstance(message, dict):
            return candidates

        for key in ("content", "text", "body", "value", "message"):
            value = message.get(key)
            if value:
                candidates.append(str(value).lower().strip())

        raw = message.get("raw_content")
        if isinstance(raw, dict):
            for key in ("id", "value", "payload", "title"):
                value = raw.get(key)
                if value:
                    candidates.append(str(value).lower().strip())

        metadata = message.get("metadata")
        if isinstance(metadata, dict):
            for key in ("selected_option", "option_id", "choice"):
                value = metadata.get(key)
                if value:
                    candidates.append(str(value).lower().strip())

        # Remove blanks and duplicates preserving order
        seen = set()
        unique_candidates = []
        for candidate in candidates:
            if candidate and candidate not in seen:
                seen.add(candidate)
                unique_candidates.append(candidate)
        return unique_candidates

    def _condition_matches(
        self,
        condition: str,
        text_candidates: List[str],
        session_state: Dict[str, Any],
    ) -> bool:
        if not condition:
            return False

        normalized = condition.strip()
        lowered = normalized.lower()

        if lowered in {"*", "always", "default", "any"}:
            return True

        if lowered.startswith("contains:"):
            term = lowered.split(":", 1)[1].strip()
            return any(term in candidate for candidate in text_candidates)

        if lowered.startswith("equals:"):
            term = lowered.split(":", 1)[1].strip()
            return any(candidate == term for candidate in text_candidates)

        if lowered.startswith("regex:"):
            pattern = lowered.split(":", 1)[1].strip()
            try:
                regex = re.compile(pattern, re.IGNORECASE)
            except re.error:
                return False
            return any(regex.search(candidate or "") for candidate in text_candidates)

        if lowered.startswith("state:"):
            expected_state = lowered.split(":", 1)[1].strip()
            last_state = str((session_state or {}).get("last_state", "")).lower()
            return last_state == expected_state

        return any(candidate == lowered for candidate in text_candidates)
