"""Responsible for loading and validating YAML flows"""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Dict, List

import yaml

from app.domain.flow import (
    FlowDefinition,
    FlowOption,
    FlowState,
    FlowTransition,
    FlowValidationError,
)

logger = logging.getLogger(__name__)


class FlowLoader:
    """Loads YAML flow definitions and keeps them cached in memory"""

    def __init__(self, flows_path: Path):
        self.flows_path = flows_path
        self._flows: Dict[str, FlowDefinition] = {}

    def load_flows(self) -> Dict[str, FlowDefinition]:
        logger.info("Loading flows from %s", self.flows_path)
        self._flows.clear()

        if not self.flows_path.exists():
            logger.warning("Flows path %s does not exist", self.flows_path)
            return self._flows

        for file in self.flows_path.glob("*.yaml"):
            try:
                with file.open("r", encoding="utf-8") as stream:
                    raw = yaml.safe_load(stream) or {}
                flow = self._parse_flow(file, raw)
                self._flows[flow.name] = flow
                logger.info("Loaded flow %s", flow.name)
            except FlowValidationError as exc:
                logger.error("Invalid flow %s: %s", file.name, exc)
            except Exception as exc:  # pragma: no cover - defensive fallback
                logger.exception("Failed to load flow %s: %s", file, exc)
        return self._flows

    def _parse_flow(self, source_path: Path, data: dict) -> FlowDefinition:
        if not isinstance(data, dict):
            raise FlowValidationError("Flow file must be a YAML mapping")

        states_block = data.get("states")
        if not isinstance(states_block, dict) or not states_block:
            raise FlowValidationError("Flow must define a non-empty 'states' mapping")

        states: Dict[str, FlowState] = {}
        for state_name, payload in states_block.items():
            states[state_name] = self._parse_state(state_name, payload)

        start_state = data.get("start_state") or data.get("start")
        if not start_state:
            raise FlowValidationError("Flow missing 'start_state'")
        if start_state not in states:
            raise FlowValidationError(f"start_state '{start_state}' not defined in states")

        for state in states.values():
            for transition in state.transitions:
                if transition.target_state not in states:
                    raise FlowValidationError(
                        f"State '{state.state}' transition references unknown state '{transition.target_state}'"
                    )

        metadata = data.get("metadata")
        if metadata is not None and not isinstance(metadata, dict):
            raise FlowValidationError("'metadata' must be a mapping if provided")

        return FlowDefinition(
            name=str(data.get("name") or source_path.stem),
            description=data.get("description"),
            start_state=start_state,
            states=states,
            metadata=metadata or {},
        )

    def _parse_state(self, state_name: str, payload: dict) -> FlowState:
        if not isinstance(payload, dict):
            raise FlowValidationError(f"State '{state_name}' must be a mapping")

        options = self._parse_options(state_name, payload.get("options"))
        transitions = self._parse_transitions(state_name, payload.get("transitions"))

        return FlowState(
            state=state_name,
            message=payload.get("message"),
            options=options,
            transitions=transitions,
        )

    def _parse_options(self, state_name: str, payload) -> List[FlowOption]:
        if payload is None:
            return []
        if not isinstance(payload, list):
            raise FlowValidationError(f"State '{state_name}' options must be a list")

        options: List[FlowOption] = []
        for idx, option in enumerate(payload):
            if not isinstance(option, dict):
                raise FlowValidationError(
                    f"State '{state_name}' option index {idx} must be a mapping"
                )
            label = option.get("label") or option.get("text")
            value = option.get("value") or option.get("id") or label
            if not label or not value:
                raise FlowValidationError(
                    f"State '{state_name}' option index {idx} missing label/value"
                )
            metadata = option.get("metadata") if isinstance(option.get("metadata"), dict) else {}
            options.append(FlowOption(label=str(label), value=str(value), metadata=metadata))
        return options

    def _parse_transitions(self, state_name: str, payload) -> List[FlowTransition]:
        if payload is None:
            return []
        if not isinstance(payload, list):
            raise FlowValidationError(f"State '{state_name}' transitions must be a list")

        transitions: List[FlowTransition] = []
        for idx, transition in enumerate(payload):
            if not isinstance(transition, dict):
                raise FlowValidationError(
                    f"State '{state_name}' transition index {idx} must be a mapping"
                )
            condition = transition.get("condition")
            target = (
                transition.get("target_state")
                or transition.get("target")
                or transition.get("next_state")
                or transition.get("next")
            )
            if not condition or not target:
                raise FlowValidationError(
                    f"State '{state_name}' transition index {idx} missing condition/target"
                )
            metadata = transition.get("metadata") if isinstance(transition.get("metadata"), dict) else {}
            transitions.append(
                FlowTransition(
                    condition=str(condition),
                    target_state=str(target),
                    metadata=metadata,
                )
            )
        return transitions

    def get_flow(self, name: str) -> FlowDefinition | None:
        return self._flows.get(name)

    def list_flows(self) -> Dict[str, FlowDefinition]:
        return self._flows

    def list_flow_names(self) -> List[str]:
        names = [path.stem for path in self.flows_path.glob("*.yaml")]
        names.sort()
        return names

    def get_flow_yaml(self, name: str) -> str:
        file_path = self.flows_path / f"{name}.yaml"
        if not file_path.exists():
            raise FlowValidationError(f"Flow '{name}' not found")
        return file_path.read_text(encoding="utf-8")

    def upsert_flow_yaml(self, name: str, yaml_content: str) -> FlowDefinition:
        if not name or not name.replace("_", "").replace("-", "").isalnum():
            raise FlowValidationError("Invalid flow name")

        try:
            raw = yaml.safe_load(yaml_content) or {}
        except yaml.YAMLError as exc:
            raise FlowValidationError(f"Invalid YAML: {exc}") from exc

        flow = self._parse_flow(self.flows_path / f"{name}.yaml", raw)

        self.flows_path.mkdir(parents=True, exist_ok=True)
        file_path = self.flows_path / f"{name}.yaml"
        file_path.write_text(yaml_content, encoding="utf-8")

        # Refresh cache with latest disk state.
        self.load_flows()
        return flow
