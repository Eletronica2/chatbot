"""Persistence for tenant WhatsApp account configuration."""
from __future__ import annotations

import asyncio
from typing import Any

from app.db.mysql import MySQLDatabase


class WhatsAppAccountRepository:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def list_by_tenant(self, tenant_id: str) -> list[dict[str, Any]]:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        return await asyncio.to_thread(
            self.database.fetch_all,
            """
            SELECT
                wa.id,
                wa.account_key,
                wa.display_name,
                wa.phone_number_id,
                wa.display_phone_number,
                wa.verify_token,
                wa.status,
                wa.is_default,
                wa.access_token_encrypted,
                wa.created_at,
                wa.updated_at,
                t.external_key AS tenant_id
            FROM whatsapp_accounts wa
            INNER JOIN tenants t ON t.id = wa.tenant_id
            WHERE wa.tenant_id = %s
            ORDER BY wa.is_default DESC, wa.display_name ASC
            """,
            (tenant_pk,),
        )

    async def get_for_tenant(self, tenant_id: str, account_key: str) -> dict[str, Any] | None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)
        return await asyncio.to_thread(
            self.database.fetch_one,
            """
            SELECT
                wa.id,
                wa.account_key,
                wa.display_name,
                wa.phone_number_id,
                wa.display_phone_number,
                wa.verify_token,
                wa.status,
                wa.is_default,
                wa.access_token_encrypted,
                wa.created_at,
                wa.updated_at,
                t.external_key AS tenant_id
            FROM whatsapp_accounts wa
            INNER JOIN tenants t ON t.id = wa.tenant_id
            WHERE wa.tenant_id = %s
              AND wa.account_key = %s
            LIMIT 1
            """,
            (tenant_pk, account_key),
        )

    async def resolve_active_account(
        self,
        *,
        tenant_id: str | None = None,
        phone_number_id: str | None = None,
        verify_token: str | None = None,
    ) -> dict[str, Any] | None:
        def _query() -> dict[str, Any] | None:
            if phone_number_id:
                return self.database.fetch_one(
                    """
                    SELECT
                        wa.id,
                        wa.account_key,
                        wa.display_name,
                        wa.phone_number_id,
                        wa.display_phone_number,
                        wa.verify_token,
                        wa.status,
                        wa.is_default,
                        wa.access_token_encrypted,
                        t.external_key AS tenant_id
                    FROM whatsapp_accounts wa
                    INNER JOIN tenants t ON t.id = wa.tenant_id
                    WHERE wa.phone_number_id = %s
                      AND wa.status = 'active'
                    LIMIT 1
                    """,
                    (phone_number_id,),
                )
            if verify_token:
                return self.database.fetch_one(
                    """
                    SELECT
                        wa.id,
                        wa.account_key,
                        wa.display_name,
                        wa.phone_number_id,
                        wa.display_phone_number,
                        wa.verify_token,
                        wa.status,
                        wa.is_default,
                        wa.access_token_encrypted,
                        t.external_key AS tenant_id
                    FROM whatsapp_accounts wa
                    INNER JOIN tenants t ON t.id = wa.tenant_id
                    WHERE wa.verify_token = %s
                      AND wa.status = 'active'
                    LIMIT 1
                    """,
                    (verify_token,),
                )
            if tenant_id:
                tenant_pk = self.database.resolve_tenant_pk(tenant_id)
                return self.database.fetch_one(
                    """
                    SELECT
                        wa.id,
                        wa.account_key,
                        wa.display_name,
                        wa.phone_number_id,
                        wa.display_phone_number,
                        wa.verify_token,
                        wa.status,
                        wa.is_default,
                        wa.access_token_encrypted,
                        t.external_key AS tenant_id
                    FROM whatsapp_accounts wa
                    INNER JOIN tenants t ON t.id = wa.tenant_id
                    WHERE wa.tenant_id = %s
                      AND wa.status = 'active'
                    ORDER BY wa.is_default DESC, wa.id ASC
                    LIMIT 1
                    """,
                    (tenant_pk,),
                )
            return None

        return await asyncio.to_thread(_query)

    async def upsert(
        self,
        *,
        tenant_id: str,
        account_key: str,
        display_name: str,
        phone_number_id: str,
        display_phone_number: str,
        verify_token: str | None,
        encrypted_access_token: str | None,
        status: str,
        is_default: bool,
    ) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _write() -> None:
            with self.database.transaction() as conn:
                with conn.cursor() as cursor:
                    if is_default:
                        cursor.execute(
                            "UPDATE whatsapp_accounts SET is_default = 0 WHERE tenant_id = %s",
                            (tenant_pk,),
                        )
                    cursor.execute(
                        """
                        INSERT INTO whatsapp_accounts (
                            tenant_id,
                            account_key,
                            display_name,
                            phone_number_id,
                            display_phone_number,
                            access_token_encrypted,
                            verify_token,
                            status,
                            is_default
                        )
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                        ON DUPLICATE KEY UPDATE
                            display_name = VALUES(display_name),
                            phone_number_id = VALUES(phone_number_id),
                            display_phone_number = VALUES(display_phone_number),
                            access_token_encrypted = COALESCE(VALUES(access_token_encrypted), access_token_encrypted),
                            verify_token = VALUES(verify_token),
                            status = VALUES(status),
                            is_default = VALUES(is_default),
                            updated_at = CURRENT_TIMESTAMP
                        """,
                        (
                            tenant_pk,
                            account_key,
                            display_name,
                            phone_number_id,
                            display_phone_number,
                            encrypted_access_token,
                            verify_token,
                            status,
                            1 if is_default else 0,
                        ),
                    )

        await asyncio.to_thread(_write)

