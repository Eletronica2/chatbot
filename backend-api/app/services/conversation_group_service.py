"""CRUD for conversation groups and membership (tenant-scoped)."""
from __future__ import annotations

import asyncio
import uuid
from datetime import datetime
from typing import Any

from fastapi import HTTPException

from app.db.mysql import MySQLDatabase


def _row_to_group(row: dict[str, Any], *, tenant_key: str) -> dict[str, Any]:
    return {
        "id": str(row.get("id") or ""),
        "tenant_id": tenant_key,
        "name": str(row.get("name") or ""),
        "description": row.get("description"),
        "is_default": bool(row.get("is_default")),
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
    }


class ConversationGroupService:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def ensure_default_group(self, tenant_id: str) -> dict[str, Any]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _ensure() -> dict[str, Any]:
            existing = self.database.fetch_one(
                """
                SELECT id, tenant_id, name, description, is_default, created_at, updated_at
                FROM conversation_groups
                WHERE tenant_id = %s AND is_default = 1
                LIMIT 1
                """,
                (tenant_pk,),
            )
            if existing is not None:
                return _row_to_group(existing, tenant_key=tenant_id)

            group_id = str(uuid.uuid4())
            self.database.execute(
                """
                INSERT INTO conversation_groups (id, tenant_id, name, description, is_default)
                VALUES (%s, %s, 'Geral', 'Grupo padrão de atendimento', 1)
                """,
                (group_id, tenant_pk),
            )
            row = self.database.fetch_one(
                """
                SELECT id, tenant_id, name, description, is_default, created_at, updated_at
                FROM conversation_groups
                WHERE id = %s
                LIMIT 1
                """,
                (group_id,),
            ) or {
                "id": group_id,
                "tenant_id": tenant_pk,
                "name": "Geral",
                "description": "Grupo padrão de atendimento",
                "is_default": 1,
                "created_at": datetime.utcnow(),
                "updated_at": datetime.utcnow(),
            }
            return _row_to_group(row, tenant_key=tenant_id)

        return await asyncio.to_thread(_ensure)

    async def list_groups(self, tenant_id: str) -> list[dict[str, Any]]:
        await self.ensure_default_group(tenant_id)
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _list() -> list[dict[str, Any]]:
            rows = self.database.fetch_all(
                """
                SELECT id, tenant_id, name, description, is_default, created_at, updated_at
                FROM conversation_groups
                WHERE tenant_id = %s
                ORDER BY is_default DESC, name ASC
                """,
                (tenant_pk,),
            )
            return [_row_to_group(row, tenant_key=tenant_id) for row in rows]

        return await asyncio.to_thread(_list)

    async def create_group(
        self,
        tenant_id: str,
        *,
        name: str,
        description: str | None = None,
    ) -> dict[str, Any]:
        await self.ensure_default_group(tenant_id)
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        cleaned = name.strip()
        if not cleaned:
            raise HTTPException(status_code=400, detail="Group name is required")
        group_id = str(uuid.uuid4())

        def _create() -> dict[str, Any]:
            self.database.execute(
                """
                INSERT INTO conversation_groups (id, tenant_id, name, description, is_default)
                VALUES (%s, %s, %s, %s, 0)
                """,
                (group_id, tenant_pk, cleaned, (description or "").strip() or None),
            )
            row = self.database.fetch_one(
                """
                SELECT id, tenant_id, name, description, is_default, created_at, updated_at
                FROM conversation_groups
                WHERE id = %s
                LIMIT 1
                """,
                (group_id,),
            ) or {
                "id": group_id,
                "name": cleaned,
                "description": description,
                "is_default": 0,
                "created_at": datetime.utcnow(),
                "updated_at": datetime.utcnow(),
            }
            return _row_to_group(row, tenant_key=tenant_id)

        try:
            return await asyncio.to_thread(_create)
        except Exception as exc:
            if "Duplicate" in str(exc) or "uq_conversation_groups" in str(exc):
                raise HTTPException(status_code=409, detail="Group name already exists") from exc
            raise

    async def update_group(
        self,
        tenant_id: str,
        group_id: str,
        *,
        name: str | None = None,
        description: str | None = None,
    ) -> dict[str, Any]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _update() -> dict[str, Any]:
            row = self.database.fetch_one(
                """
                SELECT id, tenant_id, name, description, is_default, created_at, updated_at
                FROM conversation_groups
                WHERE id = %s AND tenant_id = %s
                LIMIT 1
                """,
                (group_id, tenant_pk),
            )
            if row is None:
                raise HTTPException(status_code=404, detail="Group not found")

            next_name = name.strip() if isinstance(name, str) and name.strip() else str(row.get("name") or "")
            next_description = (
                description.strip()
                if isinstance(description, str)
                else row.get("description")
            )
            self.database.execute(
                """
                UPDATE conversation_groups
                SET name = %s, description = %s, updated_at = CURRENT_TIMESTAMP
                WHERE id = %s AND tenant_id = %s
                """,
                (next_name, next_description, group_id, tenant_pk),
            )
            updated = self.database.fetch_one(
                """
                SELECT id, tenant_id, name, description, is_default, created_at, updated_at
                FROM conversation_groups
                WHERE id = %s AND tenant_id = %s
                LIMIT 1
                """,
                (group_id, tenant_pk),
            ) or row
            return _row_to_group(updated, tenant_key=tenant_id)

        return await asyncio.to_thread(_update)

    async def delete_group(self, tenant_id: str, group_id: str) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _delete() -> None:
            row = self.database.fetch_one(
                """
                SELECT id, is_default
                FROM conversation_groups
                WHERE id = %s AND tenant_id = %s
                LIMIT 1
                """,
                (group_id, tenant_pk),
            )
            if row is None:
                raise HTTPException(status_code=404, detail="Group not found")
            if bool(row.get("is_default")):
                raise HTTPException(status_code=400, detail="Cannot delete the default group")
            self.database.execute(
                "DELETE FROM conversation_groups WHERE id = %s AND tenant_id = %s",
                (group_id, tenant_pk),
            )

        await asyncio.to_thread(_delete)

    async def set_members(
        self,
        tenant_id: str,
        group_id: str,
        user_ids: list[str],
    ) -> list[dict[str, Any]]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        cleaned = [str(uid).strip() for uid in user_ids if str(uid).strip()]

        def _set() -> list[dict[str, Any]]:
            group = self.database.fetch_one(
                """
                SELECT id FROM conversation_groups
                WHERE id = %s AND tenant_id = %s
                LIMIT 1
                """,
                (group_id, tenant_pk),
            )
            if group is None:
                raise HTTPException(status_code=404, detail="Group not found")

            if cleaned:
                placeholders = ", ".join(["%s"] * len(cleaned))
                valid_rows = self.database.fetch_all(
                    f"""
                    SELECT CAST(id AS CHAR) AS user_id
                    FROM users
                    WHERE tenant_id = %s AND CAST(id AS CHAR) IN ({placeholders})
                    """,
                    (tenant_pk, *cleaned),
                )
                valid_ids = {str(r["user_id"]) for r in valid_rows}
                invalid = [uid for uid in cleaned if uid not in valid_ids]
                if invalid:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Users not in tenant: {', '.join(invalid)}",
                    )

            self.database.execute(
                "DELETE FROM conversation_group_members WHERE group_id = %s AND tenant_id = %s",
                (group_id, tenant_pk),
            )
            for user_id in cleaned:
                self.database.execute(
                    """
                    INSERT INTO conversation_group_members (tenant_id, group_id, user_id)
                    VALUES (%s, %s, %s)
                    """,
                    (tenant_pk, group_id, user_id),
                )
            return self._list_members_sync(tenant_pk, group_id)

        return await asyncio.to_thread(_set)

    async def list_members(self, tenant_id: str, group_id: str) -> list[dict[str, Any]]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _list() -> list[dict[str, Any]]:
            group = self.database.fetch_one(
                """
                SELECT id FROM conversation_groups
                WHERE id = %s AND tenant_id = %s
                LIMIT 1
                """,
                (group_id, tenant_pk),
            )
            if group is None:
                raise HTTPException(status_code=404, detail="Group not found")
            return self._list_members_sync(tenant_pk, group_id)

        return await asyncio.to_thread(_list)

    def _list_members_sync(self, tenant_pk: int, group_id: str) -> list[dict[str, Any]]:
        rows = self.database.fetch_all(
            """
            SELECT m.user_id, m.created_at, u.email, u.display_name, u.role
            FROM conversation_group_members m
            LEFT JOIN users u ON CAST(u.id AS CHAR) = m.user_id AND u.tenant_id = m.tenant_id
            WHERE m.group_id = %s AND m.tenant_id = %s
            ORDER BY m.created_at ASC
            """,
            (group_id, tenant_pk),
        )
        return [
            {
                "user_id": str(row.get("user_id") or ""),
                "email": row.get("email"),
                "display_name": row.get("display_name"),
                "role": row.get("role"),
                "created_at": row.get("created_at"),
            }
            for row in rows
        ]
