"""Persistence layer for flow base snapshots."""
from __future__ import annotations

import asyncio
from typing import Any

from app.db.mysql import MySQLDatabase


class FlowSnapshotRepository:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def get(self, *, tenant_id: str, flow_name: str) -> dict[str, Any] | None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _query() -> dict[str, Any] | None:
            return self.database.fetch_one(
                """
                SELECT
                    id,
                    yaml_content,
                    source,
                    created_by_user_id,
                    created_at,
                    updated_at
                FROM flow_base_snapshots
                WHERE tenant_id = %s AND flow_key = %s
                LIMIT 1
                """,
                (tenant_pk, flow_name),
            )

        return await asyncio.to_thread(_query)

    async def upsert(
        self,
        *,
        tenant_id: str,
        flow_name: str,
        yaml_content: str,
        source: str = "auto",
        created_by_user_id: int | None = None,
        overwrite: bool = False,
    ) -> dict[str, Any] | None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _upsert() -> dict[str, Any] | None:
            existing = self.database.fetch_one(
                "SELECT id FROM flow_base_snapshots WHERE tenant_id = %s AND flow_key = %s LIMIT 1",
                (tenant_pk, flow_name),
            )
            if existing and not overwrite:
                return self.database.fetch_one(
                    """
                    SELECT id, yaml_content, source, created_by_user_id, created_at, updated_at
                    FROM flow_base_snapshots
                    WHERE id = %s
                    """,
                    (existing["id"],),
                )
            if existing:
                self.database.execute(
                    """
                    UPDATE flow_base_snapshots
                    SET yaml_content = %s,
                        source = %s,
                        created_by_user_id = %s,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = %s
                    """,
                    (yaml_content, source, created_by_user_id, existing["id"]),
                )
                snapshot_id = int(existing["id"])
            else:
                snapshot_id = self.database.insert(
                    """
                    INSERT INTO flow_base_snapshots (
                        tenant_id, flow_key, yaml_content, source, created_by_user_id
                    )
                    VALUES (%s, %s, %s, %s, %s)
                    """,
                    (tenant_pk, flow_name, yaml_content, source, created_by_user_id),
                )
            return self.database.fetch_one(
                """
                SELECT id, yaml_content, source, created_by_user_id, created_at, updated_at
                FROM flow_base_snapshots
                WHERE id = %s
                """,
                (snapshot_id,),
            )

        return await asyncio.to_thread(_upsert)

    async def ensure_base(
        self,
        *,
        tenant_id: str,
        flow_name: str,
        yaml_content: str,
        source: str = "auto",
        created_by_user_id: int | None = None,
    ) -> dict[str, Any] | None:
        """Create the base snapshot only if it does not already exist."""
        return await self.upsert(
            tenant_id=tenant_id,
            flow_name=flow_name,
            yaml_content=yaml_content,
            source=source,
            created_by_user_id=created_by_user_id,
            overwrite=False,
        )
