"""Per-user quick replies (tenant-scoped, owner-only mutations)."""
from __future__ import annotations

import asyncio
import uuid
from datetime import datetime
from typing import Any

from fastapi import HTTPException

from app.db.mysql import MySQLDatabase


def normalize_shortcut(raw: str) -> str:
    value = (raw or "").strip()
    if not value:
        raise HTTPException(status_code=400, detail="Shortcut is required")
    if not value.startswith("/"):
        value = f"/{value}"
    return value[:64]


def _row_to_reply(row: dict[str, Any], *, tenant_key: str) -> dict[str, Any]:
    return {
        "id": str(row.get("id") or ""),
        "tenant_id": tenant_key,
        "user_id": str(row.get("user_id") or ""),
        "title": str(row.get("title") or ""),
        "shortcut": str(row.get("shortcut") or ""),
        "content": str(row.get("content") or ""),
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
    }


class QuickReplyService:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def list_for_user(self, tenant_id: str, user_id: str) -> list[dict[str, Any]]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _list() -> list[dict[str, Any]]:
            rows = self.database.fetch_all(
                """
                SELECT id, tenant_id, user_id, title, shortcut, content, created_at, updated_at
                FROM quick_replies
                WHERE tenant_id = %s AND user_id = %s
                ORDER BY title ASC
                """,
                (tenant_pk, user_id),
            )
            return [_row_to_reply(row, tenant_key=tenant_id) for row in rows]

        return await asyncio.to_thread(_list)

    async def create(
        self,
        tenant_id: str,
        user_id: str,
        *,
        title: str,
        shortcut: str,
        content: str,
    ) -> dict[str, Any]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        cleaned_title = title.strip()
        cleaned_content = content.strip()
        if not cleaned_title:
            raise HTTPException(status_code=400, detail="Title is required")
        if not cleaned_content:
            raise HTTPException(status_code=400, detail="Content is required")
        normalized = normalize_shortcut(shortcut)
        reply_id = str(uuid.uuid4())

        def _create() -> dict[str, Any]:
            self.database.execute(
                """
                INSERT INTO quick_replies (id, tenant_id, user_id, title, shortcut, content)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (reply_id, tenant_pk, user_id, cleaned_title, normalized, cleaned_content),
            )
            row = self.database.fetch_one(
                """
                SELECT id, tenant_id, user_id, title, shortcut, content, created_at, updated_at
                FROM quick_replies WHERE id = %s LIMIT 1
                """,
                (reply_id,),
            ) or {
                "id": reply_id,
                "user_id": user_id,
                "title": cleaned_title,
                "shortcut": normalized,
                "content": cleaned_content,
                "created_at": datetime.utcnow(),
                "updated_at": datetime.utcnow(),
            }
            return _row_to_reply(row, tenant_key=tenant_id)

        try:
            return await asyncio.to_thread(_create)
        except Exception as exc:
            if "Duplicate" in str(exc) or "uq_quick_replies" in str(exc):
                raise HTTPException(status_code=409, detail="Shortcut already exists") from exc
            raise

    async def update(
        self,
        tenant_id: str,
        user_id: str,
        reply_id: str,
        *,
        title: str | None = None,
        shortcut: str | None = None,
        content: str | None = None,
    ) -> dict[str, Any]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _update() -> dict[str, Any]:
            row = self.database.fetch_one(
                """
                SELECT id, tenant_id, user_id, title, shortcut, content, created_at, updated_at
                FROM quick_replies
                WHERE id = %s AND tenant_id = %s
                LIMIT 1
                """,
                (reply_id, tenant_pk),
            )
            if row is None:
                raise HTTPException(status_code=404, detail="Quick reply not found")
            if str(row.get("user_id") or "") != user_id:
                raise HTTPException(status_code=403, detail="Only the owner can update this reply")

            next_title = title.strip() if isinstance(title, str) and title.strip() else str(row.get("title") or "")
            next_content = (
                content.strip()
                if isinstance(content, str) and content.strip()
                else str(row.get("content") or "")
            )
            next_shortcut = (
                normalize_shortcut(shortcut)
                if isinstance(shortcut, str) and shortcut.strip()
                else str(row.get("shortcut") or "")
            )
            self.database.execute(
                """
                UPDATE quick_replies
                SET title = %s, shortcut = %s, content = %s, updated_at = CURRENT_TIMESTAMP
                WHERE id = %s AND tenant_id = %s AND user_id = %s
                """,
                (next_title, next_shortcut, next_content, reply_id, tenant_pk, user_id),
            )
            updated = self.database.fetch_one(
                """
                SELECT id, tenant_id, user_id, title, shortcut, content, created_at, updated_at
                FROM quick_replies WHERE id = %s LIMIT 1
                """,
                (reply_id,),
            ) or row
            return _row_to_reply(updated, tenant_key=tenant_id)

        return await asyncio.to_thread(_update)

    async def delete(self, tenant_id: str, user_id: str, reply_id: str) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _delete() -> None:
            row = self.database.fetch_one(
                """
                SELECT id, user_id FROM quick_replies
                WHERE id = %s AND tenant_id = %s
                LIMIT 1
                """,
                (reply_id, tenant_pk),
            )
            if row is None:
                raise HTTPException(status_code=404, detail="Quick reply not found")
            if str(row.get("user_id") or "") != user_id:
                raise HTTPException(status_code=403, detail="Only the owner can delete this reply")
            self.database.execute(
                "DELETE FROM quick_replies WHERE id = %s AND tenant_id = %s AND user_id = %s",
                (reply_id, tenant_pk, user_id),
            )

        await asyncio.to_thread(_delete)
