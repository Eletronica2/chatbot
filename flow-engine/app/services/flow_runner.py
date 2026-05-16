"""Core conversational flow runner"""
from __future__ import annotations

import re
import unicodedata
from typing import Any, Dict, List, Optional

from app.domain.flow import FlowDefinition, FlowExecutionRequest, FlowExecutionResponse, FlowState
from app.services.business_hours import apply_contextual_cta


class FlowRunner:
    """Evaluates flow transitions and produces structured responses"""

    # Maximum number of silent-state hops to prevent infinite loops
    _MAX_SILENT_HOPS = 5

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

        # Collect user input into collected_data if the current state has a 'collect' field
        current_state_for_collect = definition.get_state(current_state_name)
        collected_data: Dict[str, Any] = dict(session_state.get("collected_data") or {})
        if (
            current_state_for_collect
            and current_state_for_collect.collect
            and text_candidates
        ):
            field_key = current_state_for_collect.collect
            collected_data[field_key] = text_candidates[0]
            session_state["collected_data"] = collected_data

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
                collected_data=collected_data,
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

        # 1. Try local state transitions first
        next_state = self._resolve_transition(
            current_state,
            definition,
            request,
            text_candidates=text_candidates,
        )
        if next_state:
            return self._build_response(
                definition,
                next_state,
                session_state,
                detected_intent=detected_intent,
                resolution_reason="transition_match",
                collected_data=collected_data,
            )

        # 2. Try global transitions
        global_next = self._check_global_transitions(
            definition,
            text_candidates,
            session_state,
        )
        if global_next:
            # Smart reentry: save current state so the flow can resume
            smart_reentry = has_previous_state and bool(session_state.get("current_state"))
            if smart_reentry:
                session_state["_reentry_state"] = current_state_name
                session_state["_reentry_flow"] = definition.name
            resp = self._build_response(
                definition,
                global_next,
                session_state,
                detected_intent=detected_intent,
                resolution_reason="global_transition",
                collected_data=collected_data,
            )
            resp.smart_reentry = smart_reentry
            return resp

        # 3. Handle first-message start if no transition matched
        if not has_previous_state:
            return self._build_response(
                definition,
                current_state,
                session_state,
                detected_intent=detected_intent,
                resolution_reason="flow_start",
                collected_data=collected_data,
            )

        # 3. Check if current state or flow has fallback_ai enabled
        if current_state.fallback_ai or definition.fallback_ai:
            bh = (definition.metadata or {}).get("business_hours")
            flow_msg = apply_contextual_cta(current_state.message or "", bh)
            resp = FlowExecutionResponse(
                handled=True,
                reply_text=None,  # AI will fill this
                detected_intent=detected_intent,
                session_state=session_state,
                metadata={
                    "flow": definition.name,
                    "state": current_state.state,
                    "resolution_reason": "fallback_ai",
                    "options": [o.model_dump() for o in current_state.options],
                    "flow_state_message": flow_msg,
                },
                collected_data=collected_data,
                requires_ai_fallback=True,
            )
            return resp

        return FlowExecutionResponse(
            handled=False,
            detected_intent=detected_intent,
            session_state=session_state,
            metadata={
                "flow": definition.name,
                "state": current_state.state,
                "error": "no_transition_match",
            },
            collected_data=collected_data,
        )

    def _build_response(
        self,
        definition: FlowDefinition,
        state: FlowState,
        session_state: Dict[str, Any],
        *,
        detected_intent: str | None = None,
        resolution_reason: str | None = None,
        collected_data: Optional[Dict[str, Any]] = None,
        _silent_hops: int = 0,
    ) -> FlowExecutionResponse:
        session_state = dict(session_state)
        session_state["last_state"] = state.state
        session_state["current_state"] = state.state
        session_state["last_flow"] = definition.name
        session_state["active_flow"] = definition.name
        if collected_data:
            session_state["collected_data"] = collected_data

        # Handle silent states: change state, follow default transition, no message
        if state.silent and _silent_hops < self._MAX_SILENT_HOPS:
            next_state = self._resolve_default_transition(state, definition)
            if next_state:
                return self._build_response(
                    definition,
                    next_state,
                    session_state,
                    detected_intent=detected_intent,
                    resolution_reason=resolution_reason,
                    collected_data=collected_data,
                    _silent_hops=_silent_hops + 1,
                )
            # Silent with no transition — just update state silently
            return FlowExecutionResponse(
                handled=False,
                detected_intent=detected_intent,
                session_state=session_state,
                metadata={
                    "flow": definition.name,
                    "state": state.state,
                    "resolution_reason": "silent_state_no_transition",
                },
                collected_data=collected_data or {},
            )

        options = [option.model_dump() for option in state.options]
        raw_message = state.message or ""
        business_hours = (definition.metadata or {}).get("business_hours")
        personalized = apply_contextual_cta(raw_message, business_hours)
        metadata: Dict[str, Any] = {
            "flow": definition.name,
            "state": state.state,
            "options": options,
            "hook": state.hook,
            "flow_state_message": personalized,
        }
        if detected_intent:
            metadata["detected_intent"] = detected_intent
        if resolution_reason:
            metadata["resolution_reason"] = resolution_reason
        if definition.fallback_ai or state.fallback_ai:
            metadata["fallback_ai_available"] = True
        if collected_data:
            metadata["collected_data"] = collected_data

        return FlowExecutionResponse(
            handled=bool(personalized.strip() or options),
            reply_text=personalized or None,
            detected_intent=detected_intent,
            session_state=session_state,
            metadata=metadata,
            requires_handoff=state.requires_handoff,
            collected_data=collected_data or {},
            requires_ai_fallback=bool(definition.fallback_ai or state.fallback_ai),
        )

    def _resolve_default_transition(
        self, state: FlowState, definition: FlowDefinition
    ) -> Optional[FlowState]:
        """Find the first 'always'/'default' transition for a silent state."""
        for transition in state.transitions:
            cond = (transition.condition or "").strip().lower()
            if cond in {"*", "always", "default", "any"}:
                return definition.get_state(transition.target_state)
        # If no default, use the first transition
        if state.transitions:
            return definition.get_state(state.transitions[0].target_state)
        return None

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

    def _check_global_transitions(
        self,
        definition: FlowDefinition,
        text_candidates: List[str],
        session_state: Dict[str, Any],
    ) -> Optional[FlowState]:
        """Check global transitions — evaluated when no local transition matches."""
        for gt in definition.global_transitions:
            if self._condition_matches(gt.condition, text_candidates, session_state):
                return definition.get_state(gt.target_state)
        return None

    def _extract_text_candidates(self, message: Dict[str, Any]) -> List[str]:
        candidates: List[str] = []
        if not isinstance(message, dict):
            return candidates

        for key in ("content", "text", "body", "value", "message"):
            value = message.get(key)
            if value:
                candidates.append(self._normalize_text(str(value)))

        raw = message.get("raw_content")
        if isinstance(raw, dict):
            for key in ("id", "value", "payload", "title"):
                value = raw.get(key)
                if value:
                    candidates.append(self._normalize_text(str(value)))

        metadata = message.get("metadata")
        if isinstance(metadata, dict):
            for key in ("selected_option", "option_id", "choice"):
                value = metadata.get(key)
                if value:
                    candidates.append(self._normalize_text(str(value)))

        # Remove blanks and duplicates preserving order
        seen = set()
        unique_candidates = []
        for candidate in candidates:
            if candidate and candidate not in seen:
                seen.add(candidate)
                unique_candidates.append(candidate)
        return unique_candidates

    def _normalize_text(self, text: str) -> str:
        """Lowercase, strip accents, and trim whitespace for robust matching."""
        stripped = (text or "").strip().lower()
        normalized = unicodedata.normalize("NFKD", stripped)
        return "".join(ch for ch in normalized if not unicodedata.combining(ch))

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

        # First, resolve aliases: if detected_intent matches an alias, find its canonical intent
        resolved_intent = self._resolve_alias(normalized_intent, definition.intent_aliases)
        # Also check if any text candidate matches an alias
        resolved_from_text = None
        for candidate in text_candidates:
            resolved_from_text = self._resolve_alias(candidate, definition.intent_aliases)
            if resolved_from_text:
                break

        effective_intents = {normalized_intent}
        if resolved_intent:
            effective_intents.add(resolved_intent)
        if resolved_from_text:
            effective_intents.add(resolved_from_text)

        for state in definition.states.values():
            if not state.intent_triggers:
                continue
            for trigger in state.intent_triggers:
                normalized_trigger = (trigger or "").strip().lower()
                if not normalized_trigger:
                    continue
                # Check exact match or substring against all effective intents
                for eff_intent in effective_intents:
                    if eff_intent and (
                        eff_intent == normalized_trigger
                        or normalized_trigger in eff_intent
                        or eff_intent in normalized_trigger
                    ):
                        return state
                # Check if any text candidate contains the trigger
                if any(normalized_trigger in candidate for candidate in text_candidates):
                    return state
        return None

    def _resolve_alias(
        self, text: str, intent_aliases: Dict[str, List[str]]
    ) -> Optional[str]:
        """Return canonical intent name if text matches any alias; else None."""
        if not text or not intent_aliases:
            return None
        normalized = self._normalize_text(text)
        for intent_name, aliases in intent_aliases.items():
            for alias in aliases:
                if alias in normalized or normalized in alias:
                    return intent_name
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
            term = self._normalize_text(lowered.split(":", 1)[1].strip())
            return any(term in candidate for candidate in text_candidates)

        if lowered.startswith("equals:"):
            term = self._normalize_text(lowered.split(":", 1)[1].strip())
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

        # Plain string equality fallback (also normalized)
        term = self._normalize_text(lowered)
        return any(candidate == term for candidate in text_candidates)
