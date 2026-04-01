"""Provisioning helpers for SaaS tenant onboarding."""
from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from typing import Any

from app.config.settings import Settings
from app.db.mysql import MySQLDatabase
from app.security.jwt_tools import hash_password
from app.services.flow_catalog_service import FlowCatalogService
from app.services.flow_service import FlowService
from app.services.subscription_service import SubscriptionService
from app.services.tenant_settings_service import TenantSettingsService

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class TenantProvisionRecord:
    tenant_id: str
    name: str
    email: str
    status: str
    plan: str
    owner_email: str | None = None
    created_at: Any = None
    updated_at: Any = None


class TenantAdminService:
    def __init__(
        self,
        database: MySQLDatabase,
        tenant_settings_service: TenantSettingsService,
        subscription_service: SubscriptionService,
        settings: Settings,
        flow_service: FlowService | None = None,
        flow_catalog_service: FlowCatalogService | None = None,
    ):
        self.database = database
        self.tenant_settings_service = tenant_settings_service
        self.subscription_service = subscription_service
        self.settings = settings
        self.flow_service = flow_service
        self.flow_catalog_service = flow_catalog_service

    async def list_tenants(self) -> list[TenantProvisionRecord]:
        rows = await asyncio.to_thread(self.database.list_tenants)
        return [await self.get_tenant(str(row.get('external_key') or '')) for row in rows if row.get('external_key')]

    async def get_tenant(self, tenant_id: str) -> TenantProvisionRecord:
        def _load() -> TenantProvisionRecord:
            row = self.database.get_tenant_record(tenant_id)
            if row is None:
                raise ValueError('Tenant nao encontrado')
            owner_row = self.database.fetch_one(
                """
                SELECT email
                FROM users
                WHERE tenant_id = %s
                ORDER BY FIELD(role, 'owner', 'superadmin', 'manager', 'agent'), id ASC
                LIMIT 1
                """,
                (row['id'],),
            ) or {}
            return TenantProvisionRecord(
                tenant_id=str(row.get('external_key') or tenant_id),
                name=str(row.get('name') or ''),
                email=str(row.get('email') or ''),
                status=str(row.get('status') or 'active'),
                plan=str(row.get('plan') or 'starter'),
                owner_email=str(owner_row.get('email') or '') or None,
                created_at=row.get('created_at'),
                updated_at=row.get('updated_at'),
            )

        return await asyncio.to_thread(_load)

    async def create_tenant(
        self,
        *,
        tenant_id: str,
        name: str,
        email: str,
        owner_name: str,
        owner_email: str,
        owner_password: str,
        plan: str = 'starter',
        monthly_message_limit: int | None = None,
    ) -> TenantProvisionRecord:
        normalized_tenant_id = self._normalize_tenant_id(tenant_id)
        if not normalized_tenant_id:
            raise ValueError('tenant_id invalido')
        if len(owner_password.strip()) < 6:
            raise ValueError('A senha do usuario deve ter pelo menos 6 caracteres')

        def _write() -> None:
            if self.database.get_tenant_record(normalized_tenant_id) is not None:
                raise ValueError('Ja existe um tenant com este identificador')
            existing_user = self.database.fetch_one(
                'SELECT id FROM users WHERE email = %s LIMIT 1',
                (owner_email.strip().lower(),),
            )
            if existing_user is not None:
                raise ValueError('Ja existe um usuario com este email')

            with self.database.transaction() as conn:
                with conn.cursor() as cursor:
                    cursor.execute(
                        """
                        INSERT INTO tenants (external_key, name, email, whatsapp_phone_number, status, plan)
                        VALUES (%s, %s, %s, NULL, 'active', %s)
                        """,
                        (
                            normalized_tenant_id,
                            name.strip(),
                            email.strip().lower(),
                            plan.strip() or 'starter',
                        ),
                    )
                    tenant_pk = int(cursor.lastrowid or 0)
                    cursor.execute(
                        """
                        INSERT INTO users (tenant_id, email, display_name, password_hash, role, status)
                        VALUES (%s, %s, %s, %s, 'owner', 'active')
                        """,
                        (
                            tenant_pk,
                            owner_email.strip().lower(),
                            owner_name.strip(),
                            hash_password(owner_password.strip()),
                        ),
                    )

        await asyncio.to_thread(_write)
        await self.tenant_settings_service.get_or_create(normalized_tenant_id)
        await self.subscription_service.update(
            normalized_tenant_id,
            plan=plan.strip() or 'starter',
            status='active',
            monthly_message_limit=monthly_message_limit,
        )
        await self.bootstrap_default_flows(normalized_tenant_id)
        return await self.get_tenant(normalized_tenant_id)

    async def bootstrap_default_flows(self, tenant_id: str) -> None:
        if (
            self.flow_service is None
            or self.flow_catalog_service is None
            or tenant_id == self.settings.DEFAULT_TENANT_ID
        ):
            return

        try:
            source_tenant_id = self.settings.DEFAULT_TENANT_ID
            source_flows = await self.flow_service.list_admin_flows(
                tenant_id=source_tenant_id
            )
            for item in source_flows:
                flow_name = str(item.get("name") or "").strip()
                if not flow_name:
                    continue
                yaml_payload = await self.flow_service.get_admin_flow_yaml(
                    flow_name,
                    tenant_id=source_tenant_id,
                )
                yaml_content = str(yaml_payload.get("yaml_content") or "").strip()
                if not yaml_content:
                    continue
                await self.flow_service.upsert_admin_flow_yaml(
                    flow_name,
                    yaml_content,
                    tenant_id=tenant_id,
                )
                await self.flow_catalog_service.save_yaml(
                    tenant_id=tenant_id,
                    flow_name=flow_name,
                    yaml_content=yaml_content,
                )
        except Exception as exc:  # pragma: no cover - bootstrap best effort
            logger.warning(
                "Could not bootstrap default flows for tenant %s: %s",
                tenant_id,
                exc,
            )

    def _normalize_tenant_id(self, value: str) -> str:
        normalized = ''.join(
            ch for ch in value.strip().lower().replace(' ', '_')
            if ch.isalnum() or ch in {'_', '-'}
        )
        return normalized
