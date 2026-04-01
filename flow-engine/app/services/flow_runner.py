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
        current_state_name = (
            session_state.get("current_state")
            or session_state.get("last_state")
            or definition.start_state
        )
        text_candidates = self._extract_text_candidates(request.message)
        detected_intent = self._extract_detected_intent(request.message)
        intent_state = self._find_state_by_intent(
            definition=definition,
            detected_intent=detected_intent,
            text_candidates=text_candidates,
        )

        has_previous_state = bool(
            session_state.get("current_state") or session_state.get("last_state")
        )
        if intent_state and (
            not has_previous_state or intent_state.state != current_state_name
        ):
            return self._build_response(
                definition,
                intent_state,
                session_state,
                detected_intent=detected_intent,
                resolution_reason="intent_match",
            )

        current_state = definition.get_state(current_state_name)
        if not current_state:
            return FlowExecutionResponse(
                handled=False,
                detected_intent=detected_intent,
                session_state=session_state,
                metadata={
                    "flow": definition.name,
                    "state": current_state_name,
                    "error": "state_not_found",
                },
            )

        if not has_previous_state:
            return self._build_response(
                definition,
                current_state,
                session_state,
                detected_intent=detected_intent,
                resolution_reason="flow_start",
            )

        next_state = self._resolve_transition(
            current_state,
            definition,
            request,
            text_candidates=text_candidates,
        )
        if not next_state:
            return FlowExecutionResponse(
                handled=False,
                detected_intent=detected_intent,
                session_state=session_state,
                metadata={
                    "flow": definition.name,
                    "state": current_state.state,
                    "error": "no_transition_match",
                },
            )

        return self._build_response(
            definition,
            next_state,
            session_state,
            detected_intent=detected_intent,
            resolution_reason="transition_match",
        )

    def _build_response(
        self,
        definition: FlowDefinition,
        state: FlowState,
        session_state: Dict[str, Any],
        *,
        detected_intent: str | None = None,
        resolution_reason: str | None = None,
    ) -> FlowExecutionResponse:
        session_state = dict(session_state)
        session_state["last_state"] = state.state
        session_state["current_state"] = state.state
        session_state["last_flow"] = definition.name
        session_state["active_flow"] = definition.name

        options = [option.model_dump() for option in state.options]
        metadata: Dict[str, Any] = {
            "flow": definition.name,
            "state": state.state,
            "options": options,
            "hook": state.hook,
        }
        if detected_intent:
            metadata["detected_intent"] = detected_intent
        if resolution_reason:
            metadata["resolution_reason"] = resolution_reason

        return FlowExecutionResponse(
            handled=bool((state.message or "").strip() or options),
            reply_text=state.message,
            detected_intent=detected_intent,
            session_state=session_state,
            metadata=metadata,
            requires_handoff=state.requires_handoff,
        )

    def _resolve_transition(
        self,
        state: FlowState,
        definition: FlowDefinition,
        request: FlowExecutionRequest,
        *,
        text_candidates: Optional[List[str]] = None,
    ) -> Optional[FlowState]:
        if not state.transitions:
            return None

        if text_candidates is None:
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

    def _extract_detected_intent(self, message: Dict[str, Any]) -> Optional[str]:
        if not isinstance(message, dict):
            return None

        metadata = message.get("metadata")
        if isinstance(metadata, dict):
            for key in ("detected_intent", "intent"):
                value = metadata.get(key)
                if isinstance(value, str) and value.strip():
                    return value.strip().lower()
        for key in ("detected_intent", "intent"):
            value = message.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip().lower()
        return None

    def _find_state_by_intent(
        self,
        *,
        definition: FlowDefinition,
        detected_intent: Optional[str],
        text_candidates: List[str],
    ) -> Optional[FlowState]:
        if not detected_intent and not text_candidates:
            return None

        normalized_intent = (detected_intent or "").strip().lower()
        for state in definition.states.values():
            if not state.intent_triggers:
                continue
            for trigger in state.intent_triggers:
                normalized_trigger = (trigger or "").strip().lower()
                if not normalized_trigger:
                    continue
                if normalized_intent and (
                    normalized_intent == normalized_trigger
                    or normalized_trigger in normalized_intent
                    or normalized_intent in normalized_trigger
                ):
                    return state
                if any(normalized_trigger in candidate for candidate in text_candidates):
                    return state
        return None

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
