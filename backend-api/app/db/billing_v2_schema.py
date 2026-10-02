"""Billing V2 schema (dual Meta billing mode, entitlement buckets, reservations).

Additive and idempotent: only CREATE TABLE IF NOT EXISTS, ADD COLUMN/INDEX when
missing and INSERT ... WHERE NOT EXISTS seeds. Mirrors
database/migrations/010_billing_v2_dual_mode.sql.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Callable

logger = logging.getLogger(__name__)

CATALOG_VERSION_V2 = "2026-10"
RATE_VERSION_BR_2026_10 = "RATE_BR_2026_10_01"

TABLES: tuple[str, ...] = (
    """
    CREATE TABLE IF NOT EXISTS billing_catalog_items (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        code VARCHAR(80) NOT NULL,
        catalog_version VARCHAR(32) NOT NULL,
        kind VARCHAR(32) NOT NULL,
        plan_key VARCHAR(50) NULL,
        label VARCHAR(120) NOT NULL,
        price DECIMAL(18,6) NULL,
        currency VARCHAR(8) NOT NULL DEFAULT 'BRL',
        operational_units INT UNSIGNED NULL,
        marketing_units INT UNSIGNED NULL,
        is_custom TINYINT(1) NOT NULL DEFAULT 0,
        status VARCHAR(32) NOT NULL DEFAULT 'active',
        sort_order INT NOT NULL DEFAULT 0,
        metadata JSON NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_billing_catalog_code (code),
        KEY idx_billing_catalog_kind_status (kind, status),
        KEY idx_billing_catalog_version (catalog_version),
        CONSTRAINT chk_billing_catalog_price CHECK (price IS NULL OR price >= 0)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS tenant_billing_config (
        tenant_id BIGINT UNSIGNED NOT NULL,
        billing_mode VARCHAR(40) NULL,
        catalog_version VARCHAR(32) NULL,
        plan_code VARCHAR(80) NULL,
        operational_allowance INT UNSIGNED NULL,
        monthly_price DECIMAL(18,6) NULL,
        campaign_policy VARCHAR(40) NULL,
        billing_v2_active_from DATETIME NULL,
        updated_by_user_id VARCHAR(64) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (tenant_id),
        KEY idx_tenant_billing_mode (billing_mode),
        CONSTRAINT fk_tenant_billing_config_tenant
            FOREIGN KEY (tenant_id) REFERENCES tenants(id)
            ON DELETE CASCADE ON UPDATE CASCADE,
        CONSTRAINT fk_tenant_billing_config_plan
            FOREIGN KEY (plan_code) REFERENCES billing_catalog_items(code)
            ON DELETE RESTRICT ON UPDATE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS billing_topup_purchases (
        id CHAR(36) NOT NULL,
        tenant_id BIGINT UNSIGNED NOT NULL,
        catalog_item_code VARCHAR(80) NOT NULL,
        unit_type VARCHAR(16) NOT NULL,
        units INT UNSIGNED NOT NULL,
        unit_price DECIMAL(18,6) NOT NULL,
        total_amount DECIMAL(18,6) NOT NULL,
        currency VARCHAR(8) NOT NULL DEFAULT 'BRL',
        catalog_version VARCHAR(32) NOT NULL,
        status VARCHAR(32) NOT NULL DEFAULT 'pending',
        provider VARCHAR(32) NOT NULL DEFAULT 'stripe_test',
        provider_session_id VARCHAR(190) NULL,
        provider_payment_id VARCHAR(190) NULL,
        created_by_user_id VARCHAR(64) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        paid_at DATETIME NULL,
        granted_at DATETIME NULL,
        PRIMARY KEY (id),
        UNIQUE KEY uq_topup_provider_session (provider_session_id),
        KEY idx_topup_tenant_created (tenant_id, created_at),
        KEY idx_topup_status (status),
        CONSTRAINT fk_topup_tenant
            FOREIGN KEY (tenant_id) REFERENCES tenants(id)
            ON DELETE CASCADE ON UPDATE CASCADE,
        CONSTRAINT fk_topup_catalog
            FOREIGN KEY (catalog_item_code) REFERENCES billing_catalog_items(code)
            ON DELETE RESTRICT ON UPDATE CASCADE,
        CONSTRAINT chk_topup_amount CHECK (total_amount >= 0 AND unit_price >= 0)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS billing_entitlement_buckets (
        id CHAR(36) NOT NULL,
        tenant_id BIGINT UNSIGNED NOT NULL,
        unit_type VARCHAR(16) NOT NULL,
        source VARCHAR(16) NOT NULL,
        granted INT UNSIGNED NOT NULL,
        available INT UNSIGNED NOT NULL,
        reserved INT UNSIGNED NOT NULL DEFAULT 0,
        consumed INT UNSIGNED NOT NULL DEFAULT 0,
        expired INT UNSIGNED NOT NULL DEFAULT 0,
        expires_at DATETIME NULL,
        cycle_start DATETIME NULL,
        cycle_end DATETIME NULL,
        catalog_item_code VARCHAR(80) NULL,
        purchase_id CHAR(36) NULL,
        grant_key VARCHAR(190) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_bucket_grant_key (grant_key),
        KEY idx_bucket_lookup (tenant_id, unit_type, expires_at),
        CONSTRAINT fk_bucket_tenant
            FOREIGN KEY (tenant_id) REFERENCES tenants(id)
            ON DELETE CASCADE ON UPDATE CASCADE,
        CONSTRAINT fk_bucket_purchase
            FOREIGN KEY (purchase_id) REFERENCES billing_topup_purchases(id)
            ON DELETE RESTRICT ON UPDATE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS billing_reservations (
        id CHAR(36) NOT NULL,
        tenant_id BIGINT UNSIGNED NOT NULL,
        bucket_id CHAR(36) NULL,
        unit_type VARCHAR(16) NOT NULL,
        units INT UNSIGNED NOT NULL DEFAULT 1,
        category VARCHAR(32) NOT NULL,
        category_source VARCHAR(64) NOT NULL,
        billing_mode VARCHAR(40) NOT NULL,
        entitlement VARCHAR(32) NOT NULL,
        source_path VARCHAR(32) NOT NULL,
        phone_number_id VARCHAR(64) NULL,
        provider_message_id VARCHAR(120) NULL,
        idempotency_key VARCHAR(190) NOT NULL,
        status VARCHAR(32) NOT NULL DEFAULT 'reserved',
        last_provider_status VARCHAR(32) NULL,
        meta_rate_card_id BIGINT UNSIGNED NULL,
        meta_unit_cost DECIMAL(18,6) NULL,
        meta_currency VARCHAR(8) NULL,
        meta_rate_version VARCHAR(64) NULL,
        commercial_unit_price DECIMAL(18,6) NULL,
        catalog_version VARCHAR(32) NULL,
        campaign_id VARCHAR(64) NULL,
        template_name VARCHAR(190) NULL,
        reconciliation_required TINYINT(1) NOT NULL DEFAULT 0,
        reconciliation_note VARCHAR(255) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        accepted_at DATETIME NULL,
        finalized_at DATETIME NULL,
        PRIMARY KEY (id),
        UNIQUE KEY uq_reservation_idempotency (tenant_id, idempotency_key),
        UNIQUE KEY uq_reservation_provider_msg (tenant_id, provider_message_id),
        KEY idx_reservation_status_created (status, created_at),
        KEY idx_reservation_tenant_created (tenant_id, created_at),
        KEY idx_reservation_category (tenant_id, category),
        KEY idx_reservation_mode (billing_mode),
        KEY idx_reservation_phone (phone_number_id),
        CONSTRAINT fk_reservation_tenant
            FOREIGN KEY (tenant_id) REFERENCES tenants(id)
            ON DELETE CASCADE ON UPDATE CASCADE,
        CONSTRAINT fk_reservation_bucket
            FOREIGN KEY (bucket_id) REFERENCES billing_entitlement_buckets(id)
            ON DELETE RESTRICT ON UPDATE CASCADE,
        CONSTRAINT fk_reservation_rate
            FOREIGN KEY (meta_rate_card_id) REFERENCES meta_rate_cards(id)
            ON DELETE RESTRICT ON UPDATE CASCADE,
        CONSTRAINT chk_reservation_units CHECK (units >= 1)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS billing_message_status (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        tenant_id BIGINT UNSIGNED NOT NULL,
        provider_message_id VARCHAR(120) NOT NULL,
        status VARCHAR(32) NOT NULL,
        phone_number_id VARCHAR(64) NULL,
        pricing_category VARCHAR(32) NULL,
        pricing_billable TINYINT(1) NULL,
        error_code VARCHAR(32) NULL,
        applied TINYINT(1) NOT NULL DEFAULT 0,
        received_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_message_status (tenant_id, provider_message_id, status),
        KEY idx_message_status_pending (applied, received_at),
        CONSTRAINT fk_message_status_tenant
            FOREIGN KEY (tenant_id) REFERENCES tenants(id)
            ON DELETE CASCADE ON UPDATE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS billing_ledger (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        tenant_id BIGINT UNSIGNED NOT NULL,
        entry_type VARCHAR(16) NOT NULL,
        unit_type VARCHAR(16) NOT NULL,
        units INT UNSIGNED NOT NULL DEFAULT 0,
        bucket_id CHAR(36) NULL,
        reservation_id CHAR(36) NULL,
        purchase_id CHAR(36) NULL,
        idempotency_key VARCHAR(190) NOT NULL,
        billing_mode VARCHAR(40) NULL,
        category VARCHAR(32) NULL,
        amount DECIMAL(18,6) NULL,
        currency VARCHAR(8) NULL,
        meta_cost DECIMAL(18,6) NULL,
        meta_rate_card_id BIGINT UNSIGNED NULL,
        catalog_version VARCHAR(32) NULL,
        reason VARCHAR(255) NULL,
        actor_user_id VARCHAR(64) NULL,
        metadata JSON NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_ledger_idempotency (tenant_id, idempotency_key),
        KEY idx_ledger_tenant_created (tenant_id, created_at),
        KEY idx_ledger_reservation (reservation_id),
        KEY idx_ledger_type (entry_type),
        CONSTRAINT fk_ledger_tenant
            FOREIGN KEY (tenant_id) REFERENCES tenants(id)
            ON DELETE CASCADE ON UPDATE CASCADE,
        CONSTRAINT chk_ledger_amount CHECK (amount IS NULL OR amount >= 0)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS billing_cost_config (
        config_key VARCHAR(80) NOT NULL,
        value DECIMAL(18,6) NULL,
        description VARCHAR(255) NULL,
        updated_by_user_id VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (config_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS ai_rate_cards (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        provider VARCHAR(32) NOT NULL,
        model VARCHAR(120) NOT NULL,
        currency VARCHAR(8) NOT NULL,
        input_per_million DECIMAL(18,6) NOT NULL,
        output_per_million DECIMAL(18,6) NOT NULL,
        cached_input_per_million DECIMAL(18,6) NULL,
        effective_from DATE NOT NULL,
        effective_to DATE NULL,
        source_reference VARCHAR(255) NULL,
        needs_review TINYINT(1) NOT NULL DEFAULT 1,
        active TINYINT(1) NOT NULL DEFAULT 1,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_ai_rate (provider, model, effective_from),
        CONSTRAINT chk_ai_rate_prices CHECK (input_per_million >= 0 AND output_per_million >= 0)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS ai_usage_events (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        tenant_id BIGINT UNSIGNED NOT NULL,
        session_id VARCHAR(64) NULL,
        inbound_message_id VARCHAR(120) NULL,
        provider VARCHAR(32) NOT NULL,
        model VARCHAR(120) NULL,
        input_tokens INT UNSIGNED NULL,
        output_tokens INT UNSIGNED NULL,
        cached_tokens INT UNSIGNED NULL,
        ai_rate_card_id BIGINT UNSIGNED NULL,
        estimated_cost DECIMAL(18,6) NULL,
        cost_currency VARCHAR(8) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_ai_usage_tenant_created (tenant_id, created_at),
        CONSTRAINT fk_ai_usage_tenant
            FOREIGN KEY (tenant_id) REFERENCES tenants(id)
            ON DELETE CASCADE ON UPDATE CASCADE,
        CONSTRAINT fk_ai_usage_rate
            FOREIGN KEY (ai_rate_card_id) REFERENCES ai_rate_cards(id)
            ON DELETE RESTRICT ON UPDATE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
)

COLUMNS: tuple[tuple[str, str, str], ...] = (
    ("meta_rate_cards", "provider", "ALTER TABLE meta_rate_cards ADD COLUMN provider VARCHAR(32) NOT NULL DEFAULT 'meta' AFTER id"),
    ("meta_rate_cards", "version_code", "ALTER TABLE meta_rate_cards ADD COLUMN version_code VARCHAR(64) NULL AFTER provider"),
    ("meta_rate_cards", "unit_price", "ALTER TABLE meta_rate_cards ADD COLUMN unit_price DECIMAL(18,6) NULL AFTER rate_micros"),
    ("meta_rate_cards", "billing_basis", "ALTER TABLE meta_rate_cards ADD COLUMN billing_basis VARCHAR(40) NOT NULL DEFAULT 'per_delivered_message' AFTER unit_price"),
    ("meta_rate_cards", "free_allowance", "ALTER TABLE meta_rate_cards ADD COLUMN free_allowance INT UNSIGNED NOT NULL DEFAULT 0 AFTER billing_basis"),
    ("meta_rate_cards", "allowance_scope", "ALTER TABLE meta_rate_cards ADD COLUMN allowance_scope VARCHAR(40) NULL AFTER free_allowance"),
    ("meta_rate_cards", "tier_min", "ALTER TABLE meta_rate_cards ADD COLUMN tier_min INT UNSIGNED NOT NULL DEFAULT 0 AFTER allowance_scope"),
    ("meta_rate_cards", "tier_max", "ALTER TABLE meta_rate_cards ADD COLUMN tier_max INT UNSIGNED NULL AFTER tier_min"),
    ("meta_rate_cards", "source_checked_at", "ALTER TABLE meta_rate_cards ADD COLUMN source_checked_at DATE NULL AFTER source_reference"),
    ("meta_rate_cards", "needs_review", "ALTER TABLE meta_rate_cards ADD COLUMN needs_review TINYINT(1) NOT NULL DEFAULT 1 AFTER notes"),
    ("meta_rate_cards", "active", "ALTER TABLE meta_rate_cards ADD COLUMN active TINYINT(1) NOT NULL DEFAULT 1 AFTER needs_review"),
    ("meta_rate_cards", "created_at", "ALTER TABLE meta_rate_cards ADD COLUMN created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER active"),
    ("usage_events", "phone_number_id", "ALTER TABLE usage_events ADD COLUMN phone_number_id VARCHAR(64) NULL AFTER provider_message_id"),
    ("usage_events", "billing_mode", "ALTER TABLE usage_events ADD COLUMN billing_mode VARCHAR(40) NULL AFTER market"),
    ("usage_events", "unit_type", "ALTER TABLE usage_events ADD COLUMN unit_type VARCHAR(16) NULL AFTER billing_mode"),
    ("usage_events", "product_units", "ALTER TABLE usage_events ADD COLUMN product_units INT UNSIGNED NOT NULL DEFAULT 0 AFTER quantity"),
    ("usage_events", "meta_unit_cost", "ALTER TABLE usage_events ADD COLUMN meta_unit_cost DECIMAL(18,6) NULL AFTER product_units"),
    ("usage_events", "meta_cost", "ALTER TABLE usage_events ADD COLUMN meta_cost DECIMAL(18,6) NULL AFTER meta_unit_cost"),
    ("usage_events", "meta_currency", "ALTER TABLE usage_events ADD COLUMN meta_currency VARCHAR(8) NULL AFTER meta_cost"),
    ("usage_events", "rate_card_id", "ALTER TABLE usage_events ADD COLUMN rate_card_id BIGINT UNSIGNED NULL AFTER meta_currency"),
    ("usage_events", "category_source", "ALTER TABLE usage_events ADD COLUMN category_source VARCHAR(64) NULL AFTER category"),
    ("usage_events", "reservation_id", "ALTER TABLE usage_events ADD COLUMN reservation_id CHAR(36) NULL AFTER rate_card_id"),
    ("usage_events", "source_path", "ALTER TABLE usage_events ADD COLUMN source_path VARCHAR(32) NULL AFTER reservation_id"),
    ("proposals", "catalog_version", "ALTER TABLE proposals ADD COLUMN catalog_version VARCHAR(32) NULL AFTER plan"),
    ("proposals", "plan_code", "ALTER TABLE proposals ADD COLUMN plan_code VARCHAR(80) NULL AFTER catalog_version"),
    ("proposals", "billing_mode", "ALTER TABLE proposals ADD COLUMN billing_mode VARCHAR(40) NULL AFTER plan_code"),
    ("proposals", "operational_volume", "ALTER TABLE proposals ADD COLUMN operational_volume INT UNSIGNED NULL AFTER monthly_message_limit"),
    ("proposals", "marketing_volume", "ALTER TABLE proposals ADD COLUMN marketing_volume INT UNSIGNED NULL AFTER operational_volume"),
    ("proposals", "marketing_estimate", "ALTER TABLE proposals ADD COLUMN marketing_estimate DECIMAL(18,6) NULL AFTER marketing_volume"),
    ("proposals", "pricing_snapshot", "ALTER TABLE proposals ADD COLUMN pricing_snapshot JSON NULL AFTER included_items"),
    ("proposals", "margin_snapshot", "ALTER TABLE proposals ADD COLUMN margin_snapshot JSON NULL AFTER pricing_snapshot"),
    ("proposals", "margin_override_reason", "ALTER TABLE proposals ADD COLUMN margin_override_reason VARCHAR(500) NULL AFTER margin_snapshot"),
    ("proposals", "margin_override_by", "ALTER TABLE proposals ADD COLUMN margin_override_by VARCHAR(64) NULL AFTER margin_override_reason"),
    ("leads", "operational_volume", "ALTER TABLE leads ADD COLUMN operational_volume VARCHAR(80) NULL AFTER monthly_volume"),
    ("leads", "marketing_volume", "ALTER TABLE leads ADD COLUMN marketing_volume VARCHAR(80) NULL AFTER operational_volume"),
)

INDEXES: tuple[tuple[str, str, str], ...] = (
    ("usage_events", "idx_usage_category", "ALTER TABLE usage_events ADD KEY idx_usage_category (tenant_id, category)"),
    ("usage_events", "idx_usage_billing_mode", "ALTER TABLE usage_events ADD KEY idx_usage_billing_mode (billing_mode)"),
    ("usage_events", "idx_usage_phone", "ALTER TABLE usage_events ADD KEY idx_usage_phone (tenant_id, phone_number_id, billing_period)"),
    ("usage_events", "idx_usage_created", "ALTER TABLE usage_events ADD KEY idx_usage_created (created_at)"),
    ("proposals", "idx_proposals_catalog", "ALTER TABLE proposals ADD KEY idx_proposals_catalog (catalog_version)"),
)

COST_CONFIG_KEYS: tuple[tuple[str, str], ...] = (
    ("target_margin", "Margem de contribuicao alvo (0.30 = 30%)"),
    ("payment_fee_percent", "Taxa percentual do processador de pagamento (0.0399 = 3,99%)"),
    ("payment_fee_fixed", "Taxa fixa por cobranca do processador (BRL)"),
    ("tax_rate", "Aliquota estimada de impostos sobre receita (0.06 = 6%)"),
    ("ai_cost_per_operational_message", "Custo estimado de IA por mensagem operacional (BRL)"),
    ("allocated_platform_cost_per_tenant", "Custo de infraestrutura alocado por tenant/mes (BRL, opcional)"),
)

_V2_ITEMS: tuple[dict[str, Any], ...] = (
    {"code": "PLAN_INICIAL_2026_10", "kind": "plan", "plan_key": "inicial", "label": "Inicial", "price": "197.00", "operational_units": 1000, "sort": 10},
    {"code": "PLAN_ESSENCIAL_2026_10", "kind": "plan", "plan_key": "essencial", "label": "Essencial", "price": "297.00", "operational_units": 3000, "sort": 20},
    {"code": "PLAN_CRESCIMENTO_2026_10", "kind": "plan", "plan_key": "crescimento", "label": "Crescimento", "price": "497.00", "operational_units": 6000, "sort": 30},
    {"code": "PLAN_PROFISSIONAL_2026_10", "kind": "plan", "plan_key": "profissional", "label": "Profissional", "price": "897.00", "operational_units": 12000, "sort": 40},
    {"code": "PLAN_EMPRESARIAL_2026_10", "kind": "plan", "plan_key": "empresarial", "label": "Empresarial (sob consulta)", "price": None, "operational_units": None, "is_custom": 1, "sort": 50},
    {"code": "TOPUP_OPERATIONAL_500_2026_10", "kind": "topup_operational", "label": "+500 mensagens operacionais", "price": "49.90", "operational_units": 500, "sort": 60},
    {"code": "TOPUP_OPERATIONAL_1000_2026_10", "kind": "topup_operational", "label": "+1.000 mensagens operacionais", "price": "89.90", "operational_units": 1000, "sort": 70},
    {
        "code": "MARKETING_CREDIT_2026_10",
        "kind": "marketing_unit",
        "label": "Credito de campanha (por mensagem entregue)",
        "price": "0.55",
        "marketing_units": 1,
        "sort": 80,
        "metadata": {"pack_sizes": [100, 500, 1000, 5000]},
    },
)

_LEGACY_ITEMS: tuple[dict[str, Any], ...] = (
    {"code": "PLAN_LEGACY_STARTER", "plan_key": "starter", "label": "Starter (legado)", "price": "99.00", "operational_units": 1000},
    {"code": "PLAN_LEGACY_GROWTH", "plan_key": "growth", "label": "Growth (legado)", "price": "249.00", "operational_units": 5000},
    {"code": "PLAN_LEGACY_PRO", "plan_key": "pro", "label": "Pro (legado)", "price": "599.00", "operational_units": 20000},
    {"code": "PLAN_LEGACY_ENTERPRISE", "plan_key": "enterprise", "label": "Enterprise (legado)", "price": "1499.00", "operational_units": 100000},
    {"code": "PLAN_LEGACY_ON_DEMAND", "plan_key": "on_demand", "label": "On demand (legado)", "price": "0.00", "operational_units": None},
)

_RATE_SEEDS_BR_2026_10: tuple[tuple[str, str], ...] = (
    ("MARKETING", "0.321700"),
    ("UTILITY", "0.035000"),
    ("AUTHENTICATION", "0.035000"),
    ("SERVICE", "0.000000"),
)


def apply(cursor, *, ensure_column: Callable[..., None], ensure_index: Callable[..., None], fetchone: Callable[..., Any]) -> None:
    for ddl in TABLES:
        cursor.execute(ddl)
    for table, column, ddl in COLUMNS:
        ensure_column(cursor, table=table, column=column, ddl=ddl)
    for table, index_name, ddl in INDEXES:
        ensure_index(cursor, table=table, index_name=index_name, ddl=ddl)
    _widen_rate_card_unique(cursor, fetchone)
    _backfill_rate_cards(cursor)
    _seed_catalog(cursor, fetchone)
    _seed_rate_cards(cursor, fetchone)
    _seed_cost_config(cursor, fetchone)


def _widen_rate_card_unique(cursor, fetchone) -> None:
    """Allow tiers: unique key gains provider + tier_min (index swap, no data change)."""
    has_v2 = fetchone(
        cursor,
        "SELECT COUNT(*) AS total FROM information_schema.STATISTICS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meta_rate_cards' AND INDEX_NAME = 'uq_meta_rate_v2'",
    )
    has_v1 = fetchone(
        cursor,
        "SELECT COUNT(*) AS total FROM information_schema.STATISTICS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meta_rate_cards' AND INDEX_NAME = 'uq_meta_rate'",
    )
    v2_exists = int((has_v2 or {}).get("total") or 0) > 0
    v1_exists = int((has_v1 or {}).get("total") or 0) > 0
    alters: list[str] = []
    if not v2_exists:
        alters.append(
            "ADD UNIQUE KEY uq_meta_rate_v2 (provider, market, currency, category, effective_from, tier_min)"
        )
    if v1_exists:
        alters.append("DROP INDEX uq_meta_rate")
    if alters:
        cursor.execute("ALTER TABLE meta_rate_cards " + ", ".join(alters))


def _backfill_rate_cards(cursor) -> None:
    cursor.execute(
        """
        UPDATE meta_rate_cards
        SET unit_price = rate_micros / 1000000
        WHERE unit_price IS NULL
        """
    )
    cursor.execute(
        """
        UPDATE meta_rate_cards
        SET version_code = CONCAT('RATE_', market, '_', DATE_FORMAT(effective_from, '%Y_%m_%d'))
        WHERE version_code IS NULL
        """
    )


def _seed_catalog(cursor, fetchone) -> None:
    for item in _V2_ITEMS:
        if fetchone(cursor, "SELECT id FROM billing_catalog_items WHERE code=%s", (item["code"],)):
            continue
        cursor.execute(
            """
            INSERT INTO billing_catalog_items
                (code, catalog_version, kind, plan_key, label, price, currency,
                 operational_units, marketing_units, is_custom, status, sort_order, metadata)
            VALUES (%s, %s, %s, %s, %s, %s, 'BRL', %s, %s, %s, 'active', %s, %s)
            """,
            (
                item["code"],
                CATALOG_VERSION_V2,
                item["kind"],
                item.get("plan_key"),
                item["label"],
                item.get("price"),
                item.get("operational_units"),
                item.get("marketing_units"),
                int(item.get("is_custom") or 0),
                int(item.get("sort") or 0),
                json.dumps(item["metadata"]) if item.get("metadata") else None,
            ),
        )
    for index, item in enumerate(_LEGACY_ITEMS):
        if fetchone(cursor, "SELECT id FROM billing_catalog_items WHERE code=%s", (item["code"],)):
            continue
        cursor.execute(
            """
            INSERT INTO billing_catalog_items
                (code, catalog_version, kind, plan_key, label, price, currency,
                 operational_units, is_custom, status, sort_order, metadata)
            VALUES (%s, 'legacy-v1', 'plan', %s, %s, %s, 'BRL', %s, 0, 'legacy', %s, %s)
            """,
            (
                item["code"],
                item["plan_key"],
                item["label"],
                item["price"],
                item.get("operational_units"),
                900 + index,
                json.dumps({"note": "Catalogo V1: limite contava mensagens recebidas. Inativo para novas vendas."}),
            ),
        )


def _seed_rate_cards(cursor, fetchone) -> None:
    for category, unit_price in _RATE_SEEDS_BR_2026_10:
        exists = fetchone(
            cursor,
            """
            SELECT id FROM meta_rate_cards
            WHERE provider='meta' AND market='BR' AND currency='BRL' AND category=%s
              AND effective_from='2026-10-01' AND tier_min=0
            """,
            (category,),
        )
        if exists:
            continue
        micros = int(round(float(unit_price) * 1_000_000))
        cursor.execute(
            """
            INSERT INTO meta_rate_cards
                (provider, version_code, market, currency, category, rate_micros, unit_price,
                 billing_basis, free_allowance, allowance_scope, tier_min, tier_max,
                 effective_from, effective_to, source_reference, source_checked_at, notes,
                 needs_review, active)
            VALUES ('meta', %s, 'BR', 'BRL', %s, %s, %s, 'per_delivered_message', 0, NULL, 0, NULL,
                    '2026-10-01', NULL, 'https://developers.facebook.com/docs/whatsapp/pricing/', NULL,
                    'Valores de negocio preservados do cadastro anterior; validar contra tabela oficial Meta',
                    1, 1)
            """,
            (RATE_VERSION_BR_2026_10, category, micros, unit_price),
        )


def _seed_cost_config(cursor, fetchone) -> None:
    for key, description in COST_CONFIG_KEYS:
        if fetchone(cursor, "SELECT config_key FROM billing_cost_config WHERE config_key=%s", (key,)):
            continue
        value = "0.300000" if key == "target_margin" else None
        cursor.execute(
            "INSERT INTO billing_cost_config (config_key, value, description) VALUES (%s, %s, %s)",
            (key, value, description),
        )
