"""Repository for admin users."""
from __future__ import annotations

import asyncio
from datetime import datetime
from typing import Any

from app.db.mysql import MySQLDatabase


class UserRepository:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def ensure_user(
        self,
        *,
        tenant_id: str,
        email: str,
        display_name: str,
        password_hash: str,
        role: str = "owner",
    ) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _ensure() -> None:
            row = self.database.fetch_one(
                "SELECT id FROM users WHERE email = %s LIMIT 1",
                (email,),
            )
            if row:
                self.database.execute(
                    """
                    UPDATE users
                    SET tenant_id = %s,
                        display_name = %s,
                        password_hash = %s,
                        role = %s,
                        status = 'active'
                    WHERE email = %s
                    """,
                    (tenant_pk, display_name, password_hash, role, email),
                )
                return
            self.database.insert(
                """
                INSERT INTO users (tenant_id, email, display_name, password_hash, role, status)
                VALUES (%s, %s, %s, %s, %s, 'active')
                """,
                (tenant_pk, email, display_name, password_hash, role),
            )

        await asyncio.to_thread(_ensure)

    async def get_by_email(self, email: str) -> dict[str, Any] | None:
        def _query() -> dict[str, Any] | None:
            return self.database.fetch_one(
                """
                SELECT
                    u.id,
                    u.email,
                    u.display_name,
                    u.password_hash,
                    u.role,
                    u.status,
                    u.created_at,
                    u.last_login_at,
                    t.external_key AS tenant_id
                FROM users u
                INNER JOIN tenants t ON t.id = u.tenant_id
                WHERE u.email = %s
                LIMIT 1
                """,
                (email,),
            )

        return await asyncio.to_thread(_query)

    async def touch_last_login(self, email: str) -> None:
        await asyncio.to_thread(
            self.database.execute,
            "UPDATE users SET last_login_at = %s WHERE email = %s",
            (datetime.utcnow(), email),
        )

    async def list_by_tenant(self, tenant_id: str) -> list[dict[str, Any]]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _query() -> list[dict[str, Any]]:
            return self.database.fetch_all(
                """
                SELECT
                    u.id,
                    u.email,
                    u.display_name,
                    u.role,
                    u.status,
                    u.created_at,
                    u.last_login_at,
                    t.external_key AS tenant_id
                FROM users u
                INNER JOIN tenants t ON t.id = u.tenant_id
                WHERE u.tenant_id = %s
                ORDER BY u.created_at ASC, u.id ASC
                """,
                (tenant_pk,),
            )

        return await asyncio.to_thread(_query)

    async def get_by_id_for_tenant(self, tenant_id: str, user_id: str) -> dict[str, Any] | None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _query() -> dict[str, Any] | None:
            return self.database.fetch_one(
                """
                SELECT
                    u.id,
                    u.email,
                    u.display_name,
                    u.password_hash,
                    u.role,
                    u.status,
                    u.created_at,
                    u.last_login_at,
                    t.external_key AS tenant_id
                FROM users u
                INNER JOIN tenants t ON t.id = u.tenant_id
                WHERE u.tenant_id = %s
                  AND u.id = %s
                LIMIT 1
                """,
                (tenant_pk, int(user_id)),
            )

        return await asyncio.to_thread(_query)

    async def create_user(
        self,
        *,
        tenant_id: str,
        email: str,
        display_name: str,
        password_hash: str,
        role: str,
        status: str,
    ) -> dict[str, Any] | None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _create() -> dict[str, Any] | None:
            user_id = self.database.insert(
                """
                INSERT INTO users (tenant_id, email, display_name, password_hash, role, status)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (tenant_pk, email, display_name, password_hash, role, status),
            )
            return self.database.fetch_one(
                """
                SELECT
                    u.id,
                    u.email,
                    u.display_name,
                    u.password_hash,
                    u.role,
                    u.status,
                    u.created_at,
                    u.last_login_at,
                    t.external_key AS tenant_id
                FROM users u
                INNER JOIN tenants t ON t.id = u.tenant_id
                WHERE u.id = %s
                LIMIT 1
                """,
                (user_id,),
            )

        return await asyncio.to_thread(_create)

    async def update_user(
        self,
        *,
        tenant_id: str,
        user_id: str,
        display_name: str | None = None,
        role: str | None = None,
        status: str | None = None,
        password_hash: str | None = None,
    ) -> dict[str, Any] | None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _update() -> dict[str, Any] | None:
            clauses: list[str] = []
            params: list[Any] = []
            if display_name is not None:
                clauses.append("display_name = %s")
                params.append(display_name)
            if role is not None:
                clauses.append("role = %s")
                params.append(role)
            if status is not None:
                clauses.append("status = %s")
                params.append(status)
            if password_hash is not None:
                clauses.append("password_hash = %s")
                params.append(password_hash)
            if not clauses:
                return self.database.fetch_one(
                    """
                    SELECT
                        u.id,
                        u.email,
                        u.display_name,
                        u.password_hash,
                        u.role,
                        u.status,
                        u.created_at,
                        u.last_login_at,
                        t.external_key AS tenant_id
                    FROM users u
                    INNER JOIN tenants t ON t.id = u.tenant_id
                    WHERE u.tenant_id = %s
                      AND u.id = %s
                    LIMIT 1
                    """,
                    (tenant_pk, int(user_id)),
                )
            params.extend([tenant_pk, int(user_id)])
            self.database.execute(
                f"""
                UPDATE users
                SET {", ".join(clauses)},
                    updated_at = CURRENT_TIMESTAMP
                WHERE tenant_id = %s
                  AND id = %s
                """,
                tuple(params),
            )
            return self.database.fetch_one(
                """
                SELECT
                    u.id,
                    u.email,
                    u.display_name,
                    u.password_hash,
                    u.role,
                    u.status,
                    u.created_at,
                    u.last_login_at,
                    t.external_key AS tenant_id
                FROM users u
                INNER JOIN tenants t ON t.id = u.tenant_id
                WHERE u.tenant_id = %s
                  AND u.id = %s
                LIMIT 1
                """,
                (tenant_pk, int(user_id)),
            )

        return await asyncio.to_thread(_update)

