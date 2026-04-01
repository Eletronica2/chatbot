"""Tenant user administration, invites and password reset flows."""
from __future__ import annotations

import asyncio
import hashlib
import secrets
from datetime import datetime, timedelta

from app.config.settings import Settings
from app.db.mysql import MySQLDatabase
from app.domain.user_admin import TenantUser, TenantUserActionToken
from app.repositories.user_repository import UserRepository
from app.security.jwt_tools import hash_password


class TenantUserService:
    def __init__(
        self,
        database: MySQLDatabase,
        user_repository: UserRepository,
        settings: Settings,
    ):
        self.database = database
        self.user_repository = user_repository
        self.settings = settings

    async def list_users(self, tenant_id: str) -> list[TenantUser]:
        rows = await self.user_repository.list_by_tenant(tenant_id)
        return [self._to_user(row) for row in rows]

    async def invite_user(
        self,
        *,
        tenant_id: str,
        email: str,
        display_name: str,
        role: str,
        created_by_user_id: str | None = None,
    ) -> TenantUserActionToken:
        normalized_email = email.strip().lower()
        existing = await self.user_repository.get_by_email(normalized_email)
        if existing is not None:
            raise ValueError("Ja existe um usuario com este email")

        placeholder_password = hash_password(secrets.token_urlsafe(24))
        row = await self.user_repository.create_user(
            tenant_id=tenant_id,
            email=normalized_email,
            display_name=display_name.strip(),
            password_hash=placeholder_password,
            role=role.strip() or "manager",
            status="invited",
        )
        if row is None:
            raise ValueError("Nao foi possivel criar o usuario")
        user = self._to_user(row)
        return await self._issue_action_token(
            tenant_id=tenant_id,
            user=user,
            token_type="invite",
            expires_in_hours=self.settings.INVITE_TOKEN_TTL_HOURS,
            created_by_user_id=created_by_user_id,
        )

    async def update_user(
        self,
        *,
        tenant_id: str,
        user_id: str,
        display_name: str | None = None,
        role: str | None = None,
        status: str | None = None,
    ) -> TenantUser:
        row = await self.user_repository.update_user(
            tenant_id=tenant_id,
            user_id=user_id,
            display_name=display_name.strip() if display_name is not None else None,
            role=role.strip() if role is not None else None,
            status=status.strip() if status is not None else None,
        )
        if row is None:
            raise ValueError("Usuario nao encontrado")
        return self._to_user(row)

    async def create_password_reset(
        self,
        *,
        tenant_id: str,
        user_id: str,
        created_by_user_id: str | None = None,
    ) -> TenantUserActionToken:
        row = await self.user_repository.get_by_id_for_tenant(tenant_id, user_id)
        if row is None:
            raise ValueError("Usuario nao encontrado")
        user = self._to_user(row)
        return await self._issue_action_token(
            tenant_id=tenant_id,
            user=user,
            token_type="reset_password",
            expires_in_hours=self.settings.RESET_TOKEN_TTL_HOURS,
            created_by_user_id=created_by_user_id,
        )

    async def complete_invite(self, *, token: str, new_password: str) -> TenantUser:
        return await self._consume_action_token(
            token=token,
            token_type="invite",
            new_password=new_password,
            activate=True,
        )

    async def complete_password_reset(self, *, token: str, new_password: str) -> TenantUser:
        return await self._consume_action_token(
            token=token,
            token_type="reset_password",
            new_password=new_password,
            activate=False,
        )

    async def _issue_action_token(
        self,
        *,
        tenant_id: str,
        user: TenantUser,
        token_type: str,
        expires_in_hours: int,
        created_by_user_id: str | None,
    ) -> TenantUserActionToken:
        raw_token = secrets.token_urlsafe(32)
        token_hash = self._hash_token(raw_token)
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        expires_at = datetime.utcnow() + timedelta(hours=max(expires_in_hours, 1))
        created_by_fk = int(created_by_user_id) if created_by_user_id and created_by_user_id.isdigit() else None
        user_fk = int(user.user_id)

        def _write() -> None:
            with self.database.transaction() as conn:
                with conn.cursor() as cursor:
                    cursor.execute(
                        """
                        UPDATE user_access_tokens
                        SET status = 'revoked',
                            updated_at = CURRENT_TIMESTAMP
                        WHERE tenant_id = %s
                          AND user_id = %s
                          AND token_type = %s
                          AND status = 'pending'
                        """,
                        (tenant_pk, user_fk, token_type),
                    )
                    cursor.execute(
                        """
                        INSERT INTO user_access_tokens (
                            tenant_id,
                            user_id,
                            email,
                            token_hash,
                            token_type,
                            status,
                            expires_at,
                            created_by_user_id
                        )
                        VALUES (%s, %s, %s, %s, %s, 'pending', %s, %s)
                        """,
                        (
                            tenant_pk,
                            user_fk,
                            user.email,
                            token_hash,
                            token_type,
                            expires_at,
                            created_by_fk,
                        ),
                    )

        await asyncio.to_thread(_write)
        action_path = "accept-invite" if token_type == "invite" else "reset-password"
        action_url = f"{self.settings.ADMIN_PANEL_URL.rstrip('/')}/#/{action_path}?token={raw_token}"
        return TenantUserActionToken(
            token_type=token_type,
            token=raw_token,
            expires_at=expires_at,
            action_url=action_url,
            user=user,
        )

    async def _consume_action_token(
        self,
        *,
        token: str,
        token_type: str,
        new_password: str,
        activate: bool,
    ) -> TenantUser:
        token_hash = self._hash_token(token)

        def _consume() -> dict:
            row = self.database.fetch_one(
                """
                SELECT
                    uat.id,
                    uat.tenant_id,
                    uat.user_id,
                    uat.status,
                    uat.expires_at,
                    u.email,
                    u.display_name,
                    u.role,
                    u.status AS user_status,
                    t.external_key AS tenant_key
                FROM user_access_tokens uat
                INNER JOIN users u ON u.id = uat.user_id
                INNER JOIN tenants t ON t.id = uat.tenant_id
                WHERE uat.token_hash = %s
                  AND uat.token_type = %s
                LIMIT 1
                """,
                (token_hash, token_type),
            )
            if row is None:
                raise ValueError("Token invalido")
            if str(row.get("status") or "") != "pending":
                raise ValueError("Token ja utilizado ou revogado")
            expires_at = row.get("expires_at")
            if expires_at is None or expires_at < datetime.utcnow():
                self.database.execute(
                    "UPDATE user_access_tokens SET status = 'expired', updated_at = CURRENT_TIMESTAMP WHERE id = %s",
                    (int(row["id"]),),
                )
                raise ValueError("Token expirado")

            user_row = self.database.fetch_one(
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
                WHERE u.id = %s
                LIMIT 1
                """,
                (int(row["user_id"]),),
            )
            if user_row is None:
                raise ValueError("Usuario nao encontrado")

            update_status = "active" if activate else str(user_row.get("status") or "active")
            self.database.execute(
                """
                UPDATE users
                SET password_hash = %s,
                    status = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                """,
                (
                    hash_password(new_password),
                    update_status,
                    int(row["user_id"]),
                ),
            )
            self.database.execute(
                """
                UPDATE user_access_tokens
                SET status = 'used',
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                """,
                (int(row["id"]),),
            )

            refreshed = self.database.fetch_one(
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
                WHERE u.id = %s
                LIMIT 1
                """,
                (int(row["user_id"]),),
            )
            if refreshed is None:
                raise ValueError("Usuario nao encontrado")
            return refreshed

        row = await asyncio.to_thread(_consume)
        return self._to_user(row)

    def _hash_token(self, raw_token: str) -> str:
        return hashlib.sha256(
            f"{self.settings.APP_SECRET_KEY}:{raw_token}".encode("utf-8")
        ).hexdigest()

    def _to_user(self, row: dict) -> TenantUser:
        return TenantUser(
            user_id=str(row.get("id") or row.get("user_id") or ""),
            tenant_id=str(row.get("tenant_id") or ""),
            email=str(row.get("email") or ""),
            display_name=str(row.get("display_name") or ""),
            role=str(row.get("role") or "owner"),
            status=str(row.get("status") or "active"),
            created_at=row.get("created_at"),
            last_login_at=row.get("last_login_at"),
        )
