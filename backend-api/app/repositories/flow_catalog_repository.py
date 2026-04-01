"""Persistence for flow metadata and YAML snapshots."""
from __future__ import annotations

import asyncio
import json

import yaml

from app.db.mysql import MySQLDatabase


class FlowCatalogRepository:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def save_yaml(self, *, tenant_id: str, flow_name: str, yaml_content: str) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        parsed = yaml.safe_load(yaml_content) or {}
        description = parsed.get("description")
        start_state = parsed.get("start_state") or parsed.get("start")
        states = parsed.get("states") if isinstance(parsed.get("states"), dict) else {}

        def _save() -> None:
            with self.database.transaction() as conn:
                with conn.cursor() as cursor:
                    cursor.execute(
                        """
                        INSERT INTO flows (tenant_id, flow_key, name, description, start_state_key, is_active)
                        VALUES (%s, %s, %s, %s, %s, 1)
                        ON DUPLICATE KEY UPDATE
                            name = VALUES(name),
                            description = VALUES(description),
                            start_state_key = VALUES(start_state_key),
                            is_active = 1,
                            updated_at = CURRENT_TIMESTAMP
                        """,
                        (tenant_pk, flow_name, flow_name, description, start_state),
                    )
                    cursor.execute(
                        "SELECT id FROM flows WHERE tenant_id = %s AND flow_key = %s LIMIT 1",
                        (tenant_pk, flow_name),
                    )
                    flow_row = cursor.fetchone() or {}
                    flow_id = int(flow_row["id"])

                    cursor.execute(
                        """
                        INSERT INTO flow_documents (tenant_id, flow_key, yaml_content, version)
                        VALUES (%s, %s, %s, 1)
                        ON DUPLICATE KEY UPDATE
                            yaml_content = VALUES(yaml_content),
                            version = version + 1,
                            updated_at = CURRENT_TIMESTAMP
                        """,
                        (tenant_pk, flow_name, yaml_content),
                    )

                    cursor.execute("DELETE FROM flow_transitions WHERE tenant_id = %s AND flow_id = %s", (tenant_pk, flow_id))
                    cursor.execute("DELETE FROM flow_states WHERE tenant_id = %s AND flow_id = %s", (tenant_pk, flow_id))

                    state_id_map: dict[str, int] = {}
                    state_order = 0
                    for state_key, state_payload in states.items():
                        payload = state_payload if isinstance(state_payload, dict) else {}
                        cursor.execute(
                            """
                            INSERT INTO flow_states (
                                tenant_id,
                                flow_id,
                                state_key,
                                display_name,
                                message,
                                intent_triggers,
                                requires_handoff,
                                integration_action,
                                sort_order
                            )
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                            """,
                            (
                                tenant_pk,
                                flow_id,
                                state_key,
                                payload.get("display_name") or state_key,
                                payload.get("message"),
                                json.dumps(payload.get("intent_triggers") or [], ensure_ascii=False),
                                1 if payload.get("requires_handoff") else 0,
                                ((payload.get("hook") or {}).get("action") if isinstance(payload.get("hook"), dict) else None),
                                state_order,
                            ),
                        )
                        state_id_map[state_key] = int(cursor.lastrowid)
                        state_order += 1

                    transition_order = 0
                    for state_key, state_payload in states.items():
                        payload = state_payload if isinstance(state_payload, dict) else {}
                        transitions = payload.get("transitions") if isinstance(payload.get("transitions"), list) else []
                        for transition in transitions:
                            if not isinstance(transition, dict):
                                continue
                            target_key = (
                                transition.get("target_state")
                                or transition.get("target")
                                or transition.get("next_state")
                                or transition.get("next")
                            )
                            if not target_key or target_key not in state_id_map:
                                continue
                            condition = str(transition.get("condition") or "")
                            transition_type = "contains"
                            match_value = condition
                            if condition.startswith("equals:"):
                                transition_type = "equals"
                                match_value = condition.split(":", 1)[1].strip()
                            elif condition.startswith("intent:"):
                                transition_type = "intent"
                                match_value = condition.split(":", 1)[1].strip()
                            elif condition.startswith("regex:"):
                                transition_type = "regex"
                                match_value = condition.split(":", 1)[1].strip()
                            cursor.execute(
                                """
                                INSERT INTO flow_transitions (
                                    tenant_id,
                                    flow_id,
                                    source_state_id,
                                    target_state_id,
                                    transition_type,
                                    match_value,
                                    sort_order
                                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                                """,
                                (
                                    tenant_pk,
                                    flow_id,
                                    state_id_map[state_key],
                                    state_id_map[target_key],
                                    transition_type,
                                    match_value,
                                    transition_order,
                                ),
                            )
                            transition_order += 1

        await asyncio.to_thread(_save)

