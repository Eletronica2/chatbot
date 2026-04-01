"""Responsible for loading and validating YAML flows."""
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
    """Loads YAML flow definitions and keeps them cached in memory."""

    def __init__(self, flows_path: Path):
        self.flows_path = flows_path
        self._flows: Dict[str, FlowDefinition] = {}
        self._tenant_flows: Dict[str, Dict[str, FlowDefinition]] = {}

    def load_flows(self) -> Dict[str, FlowDefinition]:
        logger.info("Loading flows from %s", self.flows_path)
        self._flows.clear()
        self._tenant_flows.clear()

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

        tenant_root = self._tenant_root()
        if tenant_root.exists():
            for tenant_dir in tenant_root.iterdir():
                if not tenant_dir.is_dir():
                    continue
                tenant_id = tenant_dir.name
                tenant_map: Dict[str, FlowDefinition] = {}
                for file in tenant_dir.glob("*.yaml"):
                    try:
                        with file.open("r", encoding="utf-8") as stream:
                            raw = yaml.safe_load(stream) or {}
                        flow = self._parse_flow(file, raw)
                        tenant_map[flow.name] = flow
                        logger.info("Loaded tenant flow %s/%s", tenant_id, flow.name)
                    except FlowValidationError as exc:
                        logger.error(
                            "Invalid tenant flow %s/%s: %s",
                            tenant_id,
                            file.name,
                            exc,
                        )
                    except Exception as exc:  # pragma: no cover
                        logger.exception(
                            "Failed to load tenant flow %s/%s: %s",
                            tenant_id,
                            file,
                            exc,
                        )
                if tenant_map:
                    self._tenant_flows[tenant_id] = tenant_map

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
        requires_handoff = bool(payload.get("requires_handoff", False))
        hook = payload.get("hook")
        if hook is None:
            hook = {}
        if not isinstance(hook, dict):
            raise FlowValidationError(f"State '{state_name}' hook must be a mapping")

        return FlowState(
            state=state_name,
            message=payload.get("message"),
            intent_triggers=self._parse_intent_triggers(
                state_name,
                payload.get("intent_triggers"),
            ),
            options=options,
            transitions=transitions,
            requires_handoff=requires_handoff,
            hook=hook,
        )

    def _parse_intent_triggers(self, state_name: str, payload) -> List[str]:
        if payload is None:
            return []
        if not isinstance(payload, list):
            raise FlowValidationError(
                f"State '{state_name}' intent_triggers must be a list"
            )

        normalized: List[str] = []
        for idx, item in enumerate(payload):
            if not isinstance(item, str):
                raise FlowValidationError(
                    f"State '{state_name}' intent_triggers index {idx} must be a string"
                )
            value = item.strip().lower()
            if value and value not in normalized:
                normalized.append(value)
        return normalized

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

    def _tenant_root(self) -> Path:
        return self.flows_path / "tenants"

    def _resolve_flow_file_path(self, name: str, tenant_id: str | None = None) -> Path:
        if tenant_id:
            return self._tenant_root() / tenant_id / f"{name}.yaml"
        return self.flows_path / f"{name}.yaml"

    def get_flow(self, name: str, tenant_id: str | None = None) -> FlowDefinition | None:
        if tenant_id:
            tenant_flow = self._tenant_flows.get(tenant_id, {}).get(name)
            if tenant_flow:
                return tenant_flow
        return self._flows.get(name)

    def list_flows(self, tenant_id: str | None = None) -> Dict[str, FlowDefinition]:
        if not tenant_id:
            return self._flows
        merged = dict(self._flows)
        merged.update(self._tenant_flows.get(tenant_id, {}))
        return merged

    def list_flow_names(self, tenant_id: str | None = None) -> List[str]:
        names = set(path.stem for path in self.flows_path.glob("*.yaml"))
        if tenant_id:
            tenant_dir = self._tenant_root() / tenant_id
            if tenant_dir.exists():
                names.update(path.stem for path in tenant_dir.glob("*.yaml"))
        sorted_names = list(names)
        sorted_names.sort()
        return sorted_names

    def get_flow_yaml(self, name: str, tenant_id: str | None = None) -> str:
        if tenant_id:
            tenant_file = self._resolve_flow_file_path(name, tenant_id)
            if tenant_file.exists():
                return tenant_file.read_text(encoding="utf-8")

        file_path = self._resolve_flow_file_path(name, None)
        if not file_path.exists():
            raise FlowValidationError(f"Flow '{name}' not found")
        return file_path.read_text(encoding="utf-8")

    def upsert_flow_yaml(
        self,
        name: str,
        yaml_content: str,
        tenant_id: str | None = None,
    ) -> FlowDefinition:
        if not name or not name.replace("_", "").replace("-", "").isalnum():
            raise FlowValidationError("Invalid flow name")

        try:
            raw = yaml.safe_load(yaml_content) or {}
        except yaml.YAMLError as exc:
            raise FlowValidationError(f"Invalid YAML: {exc}") from exc

        file_path = self._resolve_flow_file_path(name, tenant_id)
        flow = self._parse_flow(file_path, raw)

        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(yaml_content, encoding="utf-8")

        # Refresh cache with latest disk state.
        self.load_flows()
        return flow

