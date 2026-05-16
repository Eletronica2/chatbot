"""Repository for landing-page leads."""
from __future__ import annotations

import asyncio
import json
from typing import Any

from app.db.mysql import MySQLDatabase


_ALLOWED_STATUSES = {"new", "contacted", "qualified", "won", "lost"}


class LeadRepository:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def create(
        self,
        *,
        name: str,
        company: str,
        segment: str | None,
        email: str,
        whatsapp: str,
        objective: str,
        monthly_volume: str | None,
        team_size: str | None,
        current_tools: str | None,
        best_contact_time: str | None,
        source: str,
        metadata: dict[str, Any] | None,
    ) -> dict[str, Any] | None:
        metadata_json = json.dumps(metadata, ensure_ascii=False) if metadata else None

        def _insert() -> dict[str, Any] | None:
            lead_id = self.database.insert(
                """
                INSERT INTO leads (
                    name,
                    company,
                    segment,
                    email,
                    whatsapp,
                    objective,
                    monthly_volume,
                    team_size,
                    current_tools,
                    best_contact_time,
                    source,
                    metadata
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    name,
                    company,
                    segment,
                    email,
                    whatsapp,
                    objective,
                    monthly_volume,
                    team_size,
                    current_tools,
                    best_contact_time,
                    source,
                    metadata_json,
                ),
            )
            return self._get_by_id(lead_id)

        return await asyncio.to_thread(_insert)

    async def list_all(
        self,
        *,
        status: str | None = None,
        search: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict[str, Any]]:
        clauses: list[str] = []
        params: list[Any] = []
        if status and status in _ALLOWED_STATUSES:
            clauses.append("l.status = %s")
            params.append(status)
        if search:
            like = f"%{search.strip()}%"
            clauses.append(
                "(l.name LIKE %s OR l.company LIKE %s OR l.email LIKE %s OR l.whatsapp LIKE %s)"
            )
            params.extend([like, like, like, like])

        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        params.extend([int(limit), int(offset)])

        def _query() -> list[dict[str, Any]]:
            return self.database.fetch_all(
                f"""
                SELECT
                    l.id,
                    l.name,
                    l.company,
                    l.segment,
                    l.email,
                    l.whatsapp,
                    l.objective,
                    l.monthly_volume,
                    l.team_size,
                    l.current_tools,
                    l.best_contact_time,
                    l.source,
                    l.status,
                    l.notes,
                    l.assigned_to,
                    l.metadata,
                    l.created_at,
                    l.updated_at
                FROM leads l
                {where}
                ORDER BY l.created_at DESC, l.id DESC
                LIMIT %s OFFSET %s
                """,
                tuple(params),
            )

        return await asyncio.to_thread(_query)

    async def count_by_status(self) -> dict[str, int]:
        def _query() -> dict[str, int]:
            rows = self.database.fetch_all(
                """
                SELECT status, COUNT(*) AS total
                FROM leads
                GROUP BY status
                """,
                (),
            )
            return {str(row.get("status") or "unknown"): int(row.get("total") or 0) for row in rows}

        return await asyncio.to_thread(_query)

    async def get_by_id(self, lead_id: int) -> dict[str, Any] | None:
        return await asyncio.to_thread(self._get_by_id, lead_id)

    async def update_lead(
        self,
        *,
        lead_id: int,
        status: str | None = None,
        notes: str | None = None,
        assigned_to: int | None = None,
    ) -> dict[str, Any] | None:
        def _update() -> dict[str, Any] | None:
            clauses: list[str] = []
            params: list[Any] = []
            if status is not None:
                if status not in _ALLOWED_STATUSES:
                    raise ValueError(f"Status invalido: {status}")
                clauses.append("status = %s")
                params.append(status)
            if notes is not None:
                clauses.append("notes = %s")
                params.append(notes)
            if assigned_to is not None:
                clauses.append("assigned_to = %s")
                params.append(int(assigned_to))
            if not clauses:
                return self._get_by_id(lead_id)
            params.append(int(lead_id))
            self.database.execute(
                f"UPDATE leads SET {', '.join(clauses)}, updated_at = CURRENT_TIMESTAMP WHERE id = %s",
                tuple(params),
            )
            return self._get_by_id(lead_id)

        return await asyncio.to_thread(_update)

    def _get_by_id(self, lead_id: int) -> dict[str, Any] | None:
        return self.database.fetch_one(
            """
            SELECT
                l.id,
                l.name,
                l.company,
                l.segment,
                l.email,
                l.whatsapp,
                l.objective,
                l.monthly_volume,
                l.team_size,
                l.current_tools,
                l.best_contact_time,
                l.source,
                l.status,
                l.notes,
                l.assigned_to,
                l.metadata,
                l.created_at,
                l.updated_at
            FROM leads l
            WHERE l.id = %s
            LIMIT 1
            """,
            (int(lead_id),),
        )
