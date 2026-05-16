"""MySQL helpers and bootstrap utilities for the backend runtime."""
from __future__ import annotations

import asyncio
import logging
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Iterator
from urllib.parse import unquote, urlparse

import pymysql
from pymysql.cursors import DictCursor

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class MySQLConfig:
    host: str
    port: int
    user: str
    password: str
    database: str


def _parse_database_url(database_url: str) -> MySQLConfig:
    parsed = urlparse(database_url)
    if parsed.scheme not in {"mysql", "mysql+pymysql"}:
        raise ValueError("DATABASE_URL must use mysql or mysql+pymysql scheme")
    if not parsed.hostname or not parsed.path:
        raise ValueError("DATABASE_URL is missing host or database name")
    return MySQLConfig(
        host=parsed.hostname,
        port=parsed.port or 3306,
        user=unquote(parsed.username or ""),
        password=unquote(parsed.password or ""),
        database=parsed.path.lstrip("/"),
    )


class MySQLDatabase:
    """Small sync wrapper around PyMySQL with async helpers via threads."""

    def __init__(self, database_url: str):
        self.config = _parse_database_url(database_url)
        self._tenant_id_cache: dict[str, int] = {}

    @contextmanager
    def connection(self) -> Iterator[pymysql.connections.Connection]:
        conn = pymysql.connect(
            host=self.config.host,
            port=self.config.port,
            user=self.config.user,
            password=self.config.password,
            database=self.config.database,
            charset="utf8mb4",
            cursorclass=DictCursor,
            autocommit=False,
            connect_timeout=10,
            read_timeout=20,
            write_timeout=20,
        )
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    def fetch_one(self, query: str, params: tuple[Any, ...] | None = None) -> dict[str, Any] | None:
        with self.connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute(query, params or ())
                return cursor.fetchone()

    def fetch_all(self, query: str, params: tuple[Any, ...] | None = None) -> list[dict[str, Any]]:
        with self.connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute(query, params or ())
                return list(cursor.fetchall())

    def execute(self, query: str, params: tuple[Any, ...] | None = None) -> int:
        with self.connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute(query, params or ())
                return int(cursor.rowcount)

    def insert(self, query: str, params: tuple[Any, ...] | None = None) -> int:
        with self.connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute(query, params or ())
                return int(cursor.lastrowid or 0)

    def transaction(self) -> Iterator[pymysql.connections.Connection]:
        return self.connection()

    async def fetch_one_async(
        self, query: str, params: tuple[Any, ...] | None = None
    ) -> dict[str, Any] | None:
        return await asyncio.to_thread(self.fetch_one, query, params)

    async def fetch_all_async(
        self, query: str, params: tuple[Any, ...] | None = None
    ) -> list[dict[str, Any]]:
        return await asyncio.to_thread(self.fetch_all, query, params)

    async def execute_async(self, query: str, params: tuple[Any, ...] | None = None) -> int:
        return await asyncio.to_thread(self.execute, query, params)

    async def insert_async(self, query: str, params: tuple[Any, ...] | None = None) -> int:
        return await asyncio.to_thread(self.insert, query, params)

    def bootstrap(
        self,
        *,
        default_tenant_key: str,
        default_tenant_name: str,
        default_tenant_email: str,
    ) -> None:
        logger.info("Bootstrapping MySQL schema complement")
        with self.connection() as conn:
            with conn.cursor() as cursor:
                self._bootstrap_schema(cursor)
                self._ensure_default_tenant(
                    cursor,
                    tenant_key=default_tenant_key,
                    tenant_name=default_tenant_name,
                    tenant_email=default_tenant_email,
                )
                self._ensure_default_subscription(cursor, default_tenant_key)

    def _bootstrap_schema(self, cursor) -> None:
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS tenant_settings (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                tenant_id BIGINT UNSIGNED NOT NULL,
                ai_enabled TINYINT(1) NOT NULL DEFAULT 1,
                flow_editing_enabled TINYINT(1) NOT NULL DEFAULT 1,
                gemini_model VARCHAR(120) NOT NULL DEFAULT 'gemini-1.5-flash-latest',
                fallback_models JSON NULL,
                available_models JSON NULL,
                debug_mode TINYINT(1) NOT NULL DEFAULT 0,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_tenant_settings_tenant (tenant_id),
                CONSTRAINT fk_tenant_settings_tenant
                    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
                    ON DELETE CASCADE ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                tenant_id BIGINT UNSIGNED NOT NULL,
                email VARCHAR(190) NOT NULL,
                display_name VARCHAR(160) NOT NULL,
                password_hash VARCHAR(255) NOT NULL,
                role VARCHAR(50) NOT NULL DEFAULT 'owner',
                status ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
                last_login_at DATETIME NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_users_email (email),
                KEY idx_users_tenant (tenant_id),
                CONSTRAINT fk_users_tenant
                    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
                    ON DELETE CASCADE ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """
        )
        cursor.execute(
            """
            ALTER TABLE users
            MODIFY COLUMN status ENUM('active', 'inactive', 'invited') NOT NULL DEFAULT 'active'
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS whatsapp_accounts (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                tenant_id BIGINT UNSIGNED NOT NULL,
                account_key VARCHAR(120) NOT NULL,
                display_name VARCHAR(160) NOT NULL,
                phone_number_id VARCHAR(64) NOT NULL,
                display_phone_number VARCHAR(32) NOT NULL,
                access_token_encrypted LONGTEXT NULL,
                verify_token VARCHAR(255) NULL,
                status ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
                is_default TINYINT(1) NOT NULL DEFAULT 0,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_whatsapp_accounts_phone_number_id (phone_number_id),
                UNIQUE KEY uq_whatsapp_accounts_tenant_key (tenant_id, account_key),
                KEY idx_whatsapp_accounts_tenant_status (tenant_id, status),
                CONSTRAINT fk_whatsapp_accounts_tenant
                    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
                    ON DELETE CASCADE ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS user_access_tokens (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                tenant_id BIGINT UNSIGNED NOT NULL,
                user_id BIGINT UNSIGNED NOT NULL,
                email VARCHAR(190) NOT NULL,
                token_hash CHAR(64) NOT NULL,
                token_type ENUM('invite', 'reset_password') NOT NULL,
                status ENUM('pending', 'used', 'expired', 'revoked') NOT NULL DEFAULT 'pending',
                expires_at DATETIME NOT NULL,
                created_by_user_id BIGINT UNSIGNED NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_user_access_tokens_hash (token_hash),
                KEY idx_user_access_tokens_tenant_user (tenant_id, user_id, token_type),
                KEY idx_user_access_tokens_status (status, expires_at),
                CONSTRAINT fk_user_access_tokens_tenant
                    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
                    ON DELETE CASCADE ON UPDATE CASCADE,
                CONSTRAINT fk_user_access_tokens_user
                    FOREIGN KEY (user_id) REFERENCES users(id)
                    ON DELETE CASCADE ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS admin_audit_logs (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                tenant_id BIGINT UNSIGNED NOT NULL,
                actor_user_id BIGINT UNSIGNED NULL,
                actor_email VARCHAR(190) NULL,
                action VARCHAR(120) NOT NULL,
                entity_type VARCHAR(80) NOT NULL,
                entity_key VARCHAR(190) NOT NULL,
                summary VARCHAR(255) NOT NULL,
                metadata JSON NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_admin_audit_logs_tenant_created (tenant_id, created_at),
                KEY idx_admin_audit_logs_action (tenant_id, action),
                CONSTRAINT fk_admin_audit_logs_tenant
                    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
                    ON DELETE CASCADE ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS email_deliveries (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                tenant_id BIGINT UNSIGNED NOT NULL,
                delivery_kind VARCHAR(80) NOT NULL,
                recipient_email VARCHAR(190) NOT NULL,
                subject VARCHAR(255) NOT NULL,
                status ENUM('sent', 'skipped', 'failed') NOT NULL DEFAULT 'sent',
                error_message TEXT NULL,
                sent_at DATETIME NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_email_deliveries_tenant_created (tenant_id, created_at),
                CONSTRAINT fk_email_deliveries_tenant
                    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
                    ON DELETE CASCADE ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS billing_customers (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                tenant_id BIGINT UNSIGNED NOT NULL,
                provider VARCHAR(40) NOT NULL DEFAULT 'stripe',
                provider_customer_id VARCHAR(120) NOT NULL,
                provider_subscription_id VARCHAR(120) NULL,
                provider_price_id VARCHAR(120) NULL,
                status ENUM('active', 'trialing', 'past_due', 'canceled', 'inactive') NOT NULL DEFAULT 'inactive',
                current_period_end DATETIME NULL,
                checkout_url TEXT NULL,
                portal_url TEXT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_billing_customers_tenant (tenant_id),
                UNIQUE KEY uq_billing_customers_provider_customer (provider_customer_id),
                KEY idx_billing_customers_status (status),
                CONSTRAINT fk_billing_customers_tenant
                    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
                    ON DELETE CASCADE ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS billing_invoices (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                tenant_id BIGINT UNSIGNED NOT NULL,
                provider_invoice_id VARCHAR(120) NOT NULL,
                provider_subscription_id VARCHAR(120) NULL,
                status ENUM('draft', 'open', 'paid', 'uncollectible', 'void', 'past_due') NOT NULL DEFAULT 'draft',
                hosted_invoice_url TEXT NULL,
                invoice_pdf_url TEXT NULL,
                amount_due INT UNSIGNED NOT NULL DEFAULT 0,
                amount_paid INT UNSIGNED NOT NULL DEFAULT 0,
                currency VARCHAR(12) NOT NULL DEFAULT 'brl',
                due_date DATETIME NULL,
                paid_at DATETIME NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_billing_invoices_provider_invoice (provider_invoice_id),
                KEY idx_billing_invoices_tenant_created (tenant_id, created_at),
                CONSTRAINT fk_billing_invoices_tenant
                    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
                    ON DELETE CASCADE ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS flow_documents (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                tenant_id BIGINT UNSIGNED NOT NULL,
                flow_key VARCHAR(120) NOT NULL,
                yaml_content LONGTEXT NOT NULL,
                version INT NOT NULL DEFAULT 1,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_flow_documents_tenant_key (tenant_id, flow_key),
                KEY idx_flow_documents_tenant (tenant_id),
                CONSTRAINT fk_flow_documents_tenant
                    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
                    ON DELETE CASCADE ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS flow_base_snapshots (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                tenant_id BIGINT UNSIGNED NOT NULL,
                flow_key VARCHAR(120) NOT NULL,
                yaml_content LONGTEXT NOT NULL,
                source VARCHAR(80) NOT NULL DEFAULT 'auto',
                created_by_user_id BIGINT UNSIGNED NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_flow_base_snapshots_tenant_flow (tenant_id, flow_key),
                KEY idx_flow_base_snapshots_tenant (tenant_id),
                CONSTRAINT fk_flow_base_snapshots_tenant
                    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
                    ON DELETE CASCADE ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS leads (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                name VARCHAR(160) NOT NULL,
                company VARCHAR(190) NOT NULL,
                segment VARCHAR(120) NULL,
                email VARCHAR(190) NOT NULL,
                whatsapp VARCHAR(32) NOT NULL,
                objective TEXT NOT NULL,
                monthly_volume VARCHAR(80) NULL,
                team_size VARCHAR(80) NULL,
                current_tools TEXT NULL,
                best_contact_time VARCHAR(80) NULL,
                source VARCHAR(80) NOT NULL DEFAULT 'landing',
                status ENUM('new', 'contacted', 'qualified', 'won', 'lost') NOT NULL DEFAULT 'new',
                notes TEXT NULL,
                assigned_to BIGINT UNSIGNED NULL,
                metadata JSON NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_leads_status (status),
                KEY idx_leads_email (email),
                KEY idx_leads_whatsapp (whatsapp),
                KEY idx_leads_created_at (created_at),
                CONSTRAINT fk_leads_assigned_to
                    FOREIGN KEY (assigned_to) REFERENCES users(id)
                    ON DELETE SET NULL ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS proposals (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                lead_id BIGINT UNSIGNED NULL,
                tenant_id BIGINT UNSIGNED NULL,
                company_name VARCHAR(190) NOT NULL,
                contact_name VARCHAR(160) NOT NULL,
                contact_email VARCHAR(190) NOT NULL,
                contact_whatsapp VARCHAR(32) NULL,
                plan VARCHAR(50) NOT NULL,
                monthly_value DECIMAL(10,2) NOT NULL,
                setup_fee DECIMAL(10,2) NOT NULL DEFAULT 0,
                monthly_message_limit INT UNSIGNED NOT NULL DEFAULT 1000,
                included_items JSON NULL,
                validity_days INT UNSIGNED NOT NULL DEFAULT 7,
                status ENUM('draft','sent','accepted','rejected') NOT NULL DEFAULT 'draft',
                notes TEXT NULL,
                created_by_user_id BIGINT UNSIGNED NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_proposals_status_created (status, created_at),
                KEY idx_proposals_lead (lead_id),
                CONSTRAINT fk_proposals_lead
                    FOREIGN KEY (lead_id) REFERENCES leads(id)
                    ON DELETE SET NULL ON UPDATE CASCADE,
                CONSTRAINT fk_proposals_tenant
                    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
                    ON DELETE SET NULL ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """
        )

        self._ensure_column(
            cursor,
            table="tenants",
            column="external_key",
            ddl="ALTER TABLE tenants ADD COLUMN external_key VARCHAR(120) NULL AFTER id",
        )
        self._ensure_index(
            cursor,
            table="tenants",
            index_name="uq_tenants_external_key",
            ddl="ALTER TABLE tenants ADD UNIQUE KEY uq_tenants_external_key (external_key)",
        )
        self._ensure_column(
            cursor,
            table="sessions",
            column="phone_number_id",
            ddl="ALTER TABLE sessions ADD COLUMN phone_number_id VARCHAR(64) NULL AFTER phone_number",
        )
        self._ensure_column(
            cursor,
            table="sessions",
            column="display_phone_number",
            ddl="ALTER TABLE sessions ADD COLUMN display_phone_number VARCHAR(32) NULL AFTER phone_number_id",
        )
        self._ensure_column(
            cursor,
            table="sessions",
            column="context",
            ddl="ALTER TABLE sessions ADD COLUMN context JSON NULL AFTER session_state",
        )
        self._ensure_column(
            cursor,
            table="sessions",
            column="last_flow",
            ddl="ALTER TABLE sessions ADD COLUMN last_flow VARCHAR(120) NULL AFTER current_state",
        )
        self._ensure_column(
            cursor,
            table="subscriptions",
            column="monthly_message_limit",
            ddl="ALTER TABLE subscriptions ADD COLUMN monthly_message_limit INT UNSIGNED NOT NULL DEFAULT 1000 AFTER renewal_date",
        )
        self._ensure_column(
            cursor,
            table="messages",
            column="external_message_id",
            ddl="ALTER TABLE messages ADD COLUMN external_message_id VARCHAR(120) NULL AFTER source",
        )
        self._ensure_column(
            cursor,
            table="messages",
            column="phone_number_id",
            ddl="ALTER TABLE messages ADD COLUMN phone_number_id VARCHAR(64) NULL AFTER external_message_id",
        )
        self._ensure_index(
            cursor,
            table="messages",
            index_name="idx_messages_external",
            ddl="ALTER TABLE messages ADD KEY idx_messages_external (tenant_id, external_message_id)",
        )
        self._ensure_column(
            cursor,
            table="conversation_logs",
            column="detected_intent",
            ddl="ALTER TABLE conversation_logs ADD COLUMN detected_intent VARCHAR(120) NULL AFTER source",
        )

    def _ensure_default_tenant(
        self,
        cursor,
        *,
        tenant_key: str,
        tenant_name: str,
        tenant_email: str,
    ) -> None:
        row = self._fetchone(
            cursor,
            "SELECT id FROM tenants WHERE external_key = %s",
            (tenant_key,),
        )
        if row:
            return

        first_row = self._fetchone(cursor, "SELECT id FROM tenants ORDER BY id ASC LIMIT 1")
        if first_row:
            cursor.execute(
                """
                UPDATE tenants
                SET external_key = %s
                WHERE id = %s
                """,
                (tenant_key, first_row["id"]),
            )
            return

        cursor.execute(
            """
            INSERT INTO tenants (external_key, name, email, status, plan)
            VALUES (%s, %s, %s, 'active', 'starter')
            """,
            (tenant_key, tenant_name, tenant_email),
        )

    def _ensure_default_subscription(self, cursor, tenant_key: str) -> None:
        tenant_row = self._fetchone(
            cursor,
            "SELECT id FROM tenants WHERE external_key = %s",
            (tenant_key,),
        )
        if not tenant_row:
            return
        tenant_pk = int(tenant_row["id"])
        existing = self._fetchone(
            cursor,
            "SELECT id FROM subscriptions WHERE tenant_id = %s",
            (tenant_pk,),
        )
        if existing:
            return
        cursor.execute(
            """
            INSERT INTO subscriptions (tenant_id, plan, status, renewal_date, monthly_message_limit)
            VALUES (%s, 'starter', 'active', %s, 1000)
            """,
            (tenant_pk, datetime.utcnow() + timedelta(days=30)),
        )

    def resolve_tenant_pk(self, tenant_key: str) -> int:
        if tenant_key in self._tenant_id_cache:
            return self._tenant_id_cache[tenant_key]
        row = self.fetch_one(
            "SELECT id FROM tenants WHERE external_key = %s",
            (tenant_key,),
        )
        if row is None:
            self.execute(
                """
                INSERT INTO tenants (external_key, name, email, status, plan)
                VALUES (%s, %s, %s, 'active', 'starter')
                """,
                (
                    tenant_key,
                    f"Tenant {tenant_key}",
                    f"{tenant_key}@tenant.local",
                ),
            )
            row = self.fetch_one(
                "SELECT id FROM tenants WHERE external_key = %s",
                (tenant_key,),
            )
        tenant_pk = int(row["id"])
        self._tenant_id_cache[tenant_key] = tenant_pk
        return tenant_pk

    def get_tenant_record(self, tenant_key: str) -> dict[str, Any] | None:
        return self.fetch_one(
            """
            SELECT id, external_key, name, email, status, plan, created_at, updated_at
            FROM tenants
            WHERE external_key = %s
            """,
            (tenant_key,),
        )

    def list_tenants(self) -> list[dict[str, Any]]:
        return self.fetch_all(
            """
            SELECT id, external_key, name, email, status, plan, created_at, updated_at
            FROM tenants
            ORDER BY created_at ASC
            """
        )

    def _fetchone(self, cursor, query: str, params: tuple[Any, ...] = ()) -> dict[str, Any] | None:
        cursor.execute(query, params)
        return cursor.fetchone()

    def _ensure_column(self, cursor, *, table: str, column: str, ddl: str) -> None:
        cursor.execute(
            """
            SELECT COUNT(*) AS total
            FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = %s
              AND TABLE_NAME = %s
              AND COLUMN_NAME = %s
            """,
            (self.config.database, table, column),
        )
        result = cursor.fetchone() or {}
        if int(result.get("total", 0) or 0) == 0:
            cursor.execute(ddl)

    def _ensure_index(self, cursor, *, table: str, index_name: str, ddl: str) -> None:
        cursor.execute(
            """
            SELECT COUNT(*) AS total
            FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = %s
              AND TABLE_NAME = %s
              AND INDEX_NAME = %s
            """,
            (self.config.database, table, index_name),
        )
        result = cursor.fetchone() or {}
        if int(result.get("total", 0) or 0) == 0:
            cursor.execute(ddl)

