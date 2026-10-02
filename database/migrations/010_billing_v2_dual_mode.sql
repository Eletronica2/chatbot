-- Billing V2 dual mode: entitlement buckets, reservations, ledger, versioned
-- catalog, effective-dated Meta rate cards, margin cost config, AI usage.
-- Additive and idempotent. No DROP TABLE / DROP COLUMN / data deletion.
-- The backend bootstrap (app/db/billing_v2_schema.py) applies the same schema.

DELIMITER $$
DROP PROCEDURE IF EXISTS atende_add_column_if_missing $$
CREATE PROCEDURE atende_add_column_if_missing(IN p_table VARCHAR(64), IN p_column VARCHAR(64), IN p_ddl TEXT)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_table AND COLUMN_NAME = p_column
    ) THEN
        SET @ddl = p_ddl;
        PREPARE stmt FROM @ddl;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END $$
DROP PROCEDURE IF EXISTS atende_add_index_if_missing $$
CREATE PROCEDURE atende_add_index_if_missing(IN p_table VARCHAR(64), IN p_index VARCHAR(64), IN p_ddl TEXT)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_table AND INDEX_NAME = p_index
    ) THEN
        SET @ddl = p_ddl;
        PREPARE stmt FROM @ddl;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END $$
DROP PROCEDURE IF EXISTS atende_drop_index_if_exists $$
CREATE PROCEDURE atende_drop_index_if_exists(IN p_table VARCHAR(64), IN p_index VARCHAR(64))
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_table AND INDEX_NAME = p_index
    ) THEN
        SET @ddl = CONCAT('ALTER TABLE `', p_table, '` DROP INDEX `', p_index, '`');
        PREPARE stmt FROM @ddl;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END $$
DELIMITER ;

-- ---------------------------------------------------------------------------
-- Rate cards: versioned, effective-dated, DECIMAL(18,6), tiers, free allowance
-- ---------------------------------------------------------------------------
CALL atende_add_column_if_missing('meta_rate_cards', 'provider', "ALTER TABLE meta_rate_cards ADD COLUMN provider VARCHAR(32) NOT NULL DEFAULT 'meta' AFTER id");
CALL atende_add_column_if_missing('meta_rate_cards', 'version_code', 'ALTER TABLE meta_rate_cards ADD COLUMN version_code VARCHAR(64) NULL AFTER provider');
CALL atende_add_column_if_missing('meta_rate_cards', 'unit_price', 'ALTER TABLE meta_rate_cards ADD COLUMN unit_price DECIMAL(18,6) NULL AFTER rate_micros');
CALL atende_add_column_if_missing('meta_rate_cards', 'billing_basis', "ALTER TABLE meta_rate_cards ADD COLUMN billing_basis VARCHAR(40) NOT NULL DEFAULT 'per_delivered_message' AFTER unit_price");
CALL atende_add_column_if_missing('meta_rate_cards', 'free_allowance', 'ALTER TABLE meta_rate_cards ADD COLUMN free_allowance INT UNSIGNED NOT NULL DEFAULT 0 AFTER billing_basis');
CALL atende_add_column_if_missing('meta_rate_cards', 'allowance_scope', 'ALTER TABLE meta_rate_cards ADD COLUMN allowance_scope VARCHAR(40) NULL AFTER free_allowance');
CALL atende_add_column_if_missing('meta_rate_cards', 'tier_min', 'ALTER TABLE meta_rate_cards ADD COLUMN tier_min INT UNSIGNED NOT NULL DEFAULT 0 AFTER allowance_scope');
CALL atende_add_column_if_missing('meta_rate_cards', 'tier_max', 'ALTER TABLE meta_rate_cards ADD COLUMN tier_max INT UNSIGNED NULL AFTER tier_min');
CALL atende_add_column_if_missing('meta_rate_cards', 'source_checked_at', 'ALTER TABLE meta_rate_cards ADD COLUMN source_checked_at DATE NULL AFTER source_reference');
CALL atende_add_column_if_missing('meta_rate_cards', 'needs_review', 'ALTER TABLE meta_rate_cards ADD COLUMN needs_review TINYINT(1) NOT NULL DEFAULT 1 AFTER notes');
CALL atende_add_column_if_missing('meta_rate_cards', 'active', 'ALTER TABLE meta_rate_cards ADD COLUMN active TINYINT(1) NOT NULL DEFAULT 1 AFTER needs_review');
CALL atende_add_column_if_missing('meta_rate_cards', 'created_at', 'ALTER TABLE meta_rate_cards ADD COLUMN created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER active');

-- Unique key gains provider + tier_min (index swap only; rows untouched).
CALL atende_add_index_if_missing('meta_rate_cards', 'uq_meta_rate_v2',
    'ALTER TABLE meta_rate_cards ADD UNIQUE KEY uq_meta_rate_v2 (provider, market, currency, category, effective_from, tier_min)');
CALL atende_drop_index_if_exists('meta_rate_cards', 'uq_meta_rate');

UPDATE meta_rate_cards SET unit_price = rate_micros / 1000000 WHERE unit_price IS NULL;
UPDATE meta_rate_cards
SET version_code = CONCAT('RATE_', market, '_', DATE_FORMAT(effective_from, '%Y_%m_%d'))
WHERE version_code IS NULL;

-- ---------------------------------------------------------------------------
-- usage_events: billing mode, product units, Meta cost snapshot, source
-- ---------------------------------------------------------------------------
CALL atende_add_column_if_missing('usage_events', 'phone_number_id', 'ALTER TABLE usage_events ADD COLUMN phone_number_id VARCHAR(64) NULL AFTER provider_message_id');
CALL atende_add_column_if_missing('usage_events', 'billing_mode', 'ALTER TABLE usage_events ADD COLUMN billing_mode VARCHAR(40) NULL AFTER market');
CALL atende_add_column_if_missing('usage_events', 'unit_type', 'ALTER TABLE usage_events ADD COLUMN unit_type VARCHAR(16) NULL AFTER billing_mode');
CALL atende_add_column_if_missing('usage_events', 'product_units', 'ALTER TABLE usage_events ADD COLUMN product_units INT UNSIGNED NOT NULL DEFAULT 0 AFTER quantity');
CALL atende_add_column_if_missing('usage_events', 'meta_unit_cost', 'ALTER TABLE usage_events ADD COLUMN meta_unit_cost DECIMAL(18,6) NULL AFTER product_units');
CALL atende_add_column_if_missing('usage_events', 'meta_cost', 'ALTER TABLE usage_events ADD COLUMN meta_cost DECIMAL(18,6) NULL AFTER meta_unit_cost');
CALL atende_add_column_if_missing('usage_events', 'meta_currency', 'ALTER TABLE usage_events ADD COLUMN meta_currency VARCHAR(8) NULL AFTER meta_cost');
CALL atende_add_column_if_missing('usage_events', 'rate_card_id', 'ALTER TABLE usage_events ADD COLUMN rate_card_id BIGINT UNSIGNED NULL AFTER meta_currency');
CALL atende_add_column_if_missing('usage_events', 'category_source', 'ALTER TABLE usage_events ADD COLUMN category_source VARCHAR(64) NULL AFTER category');
CALL atende_add_column_if_missing('usage_events', 'reservation_id', 'ALTER TABLE usage_events ADD COLUMN reservation_id CHAR(36) NULL AFTER rate_card_id');
CALL atende_add_column_if_missing('usage_events', 'source_path', 'ALTER TABLE usage_events ADD COLUMN source_path VARCHAR(32) NULL AFTER reservation_id');
CALL atende_add_index_if_missing('usage_events', 'idx_usage_category', 'ALTER TABLE usage_events ADD KEY idx_usage_category (tenant_id, category)');
CALL atende_add_index_if_missing('usage_events', 'idx_usage_billing_mode', 'ALTER TABLE usage_events ADD KEY idx_usage_billing_mode (billing_mode)');
CALL atende_add_index_if_missing('usage_events', 'idx_usage_phone', 'ALTER TABLE usage_events ADD KEY idx_usage_phone (tenant_id, phone_number_id, billing_period)');
CALL atende_add_index_if_missing('usage_events', 'idx_usage_created', 'ALTER TABLE usage_events ADD KEY idx_usage_created (created_at)');

-- ---------------------------------------------------------------------------
-- Leads / proposals: separate operational and marketing volumes + snapshots
-- ---------------------------------------------------------------------------
CALL atende_add_column_if_missing('leads', 'operational_volume', 'ALTER TABLE leads ADD COLUMN operational_volume VARCHAR(80) NULL AFTER monthly_volume');
CALL atende_add_column_if_missing('leads', 'marketing_volume', 'ALTER TABLE leads ADD COLUMN marketing_volume VARCHAR(80) NULL AFTER operational_volume');
CALL atende_add_column_if_missing('proposals', 'catalog_version', 'ALTER TABLE proposals ADD COLUMN catalog_version VARCHAR(32) NULL AFTER plan');
CALL atende_add_column_if_missing('proposals', 'plan_code', 'ALTER TABLE proposals ADD COLUMN plan_code VARCHAR(80) NULL AFTER catalog_version');
CALL atende_add_column_if_missing('proposals', 'billing_mode', 'ALTER TABLE proposals ADD COLUMN billing_mode VARCHAR(40) NULL AFTER plan_code');
CALL atende_add_column_if_missing('proposals', 'operational_volume', 'ALTER TABLE proposals ADD COLUMN operational_volume INT UNSIGNED NULL AFTER monthly_message_limit');
CALL atende_add_column_if_missing('proposals', 'marketing_volume', 'ALTER TABLE proposals ADD COLUMN marketing_volume INT UNSIGNED NULL AFTER operational_volume');
CALL atende_add_column_if_missing('proposals', 'marketing_estimate', 'ALTER TABLE proposals ADD COLUMN marketing_estimate DECIMAL(18,6) NULL AFTER marketing_volume');
CALL atende_add_column_if_missing('proposals', 'pricing_snapshot', 'ALTER TABLE proposals ADD COLUMN pricing_snapshot JSON NULL AFTER included_items');
CALL atende_add_column_if_missing('proposals', 'margin_snapshot', 'ALTER TABLE proposals ADD COLUMN margin_snapshot JSON NULL AFTER pricing_snapshot');
CALL atende_add_column_if_missing('proposals', 'margin_override_reason', 'ALTER TABLE proposals ADD COLUMN margin_override_reason VARCHAR(500) NULL AFTER margin_snapshot');
CALL atende_add_column_if_missing('proposals', 'margin_override_by', 'ALTER TABLE proposals ADD COLUMN margin_override_by VARCHAR(64) NULL AFTER margin_override_reason');
CALL atende_add_index_if_missing('proposals', 'idx_proposals_catalog', 'ALTER TABLE proposals ADD KEY idx_proposals_catalog (catalog_version)');

-- ---------------------------------------------------------------------------
-- New tables
-- ---------------------------------------------------------------------------
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    CONSTRAINT fk_tenant_billing_config_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_tenant_billing_config_plan FOREIGN KEY (plan_code) REFERENCES billing_catalog_items(code) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    CONSTRAINT fk_topup_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_topup_catalog FOREIGN KEY (catalog_item_code) REFERENCES billing_catalog_items(code) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_topup_amount CHECK (total_amount >= 0 AND unit_price >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    CONSTRAINT fk_bucket_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_bucket_purchase FOREIGN KEY (purchase_id) REFERENCES billing_topup_purchases(id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    CONSTRAINT fk_reservation_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_reservation_bucket FOREIGN KEY (bucket_id) REFERENCES billing_entitlement_buckets(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_reservation_rate FOREIGN KEY (meta_rate_card_id) REFERENCES meta_rate_cards(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_reservation_units CHECK (units >= 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    CONSTRAINT fk_message_status_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    CONSTRAINT fk_ledger_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_ledger_amount CHECK (amount IS NULL OR amount >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS billing_cost_config (
    config_key VARCHAR(80) NOT NULL,
    value DECIMAL(18,6) NULL,
    description VARCHAR(255) NULL,
    updated_by_user_id VARCHAR(64) NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (config_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    CONSTRAINT fk_ai_usage_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ai_usage_rate FOREIGN KEY (ai_rate_card_id) REFERENCES ai_rate_cards(id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Seeds: catalog V2 (2026-10), legacy V1 (inactive for new sales),
-- rate card version RATE_BR_2026_10_01 (needs_review), cost config keys.
-- ---------------------------------------------------------------------------
INSERT INTO billing_catalog_items (code, catalog_version, kind, plan_key, label, price, operational_units, marketing_units, is_custom, status, sort_order, metadata)
SELECT * FROM (
    SELECT 'PLAN_INICIAL_2026_10' AS code, '2026-10' AS cv, 'plan' AS kind, 'inicial' AS pk, 'Inicial' AS label, 197.00 AS price, 1000 AS ou, NULL AS mu, 0 AS ic, 'active' AS st, 10 AS so, NULL AS md
    UNION ALL SELECT 'PLAN_ESSENCIAL_2026_10', '2026-10', 'plan', 'essencial', 'Essencial', 297.00, 3000, NULL, 0, 'active', 20, NULL
    UNION ALL SELECT 'PLAN_CRESCIMENTO_2026_10', '2026-10', 'plan', 'crescimento', 'Crescimento', 497.00, 6000, NULL, 0, 'active', 30, NULL
    UNION ALL SELECT 'PLAN_PROFISSIONAL_2026_10', '2026-10', 'plan', 'profissional', 'Profissional', 897.00, 12000, NULL, 0, 'active', 40, NULL
    UNION ALL SELECT 'PLAN_EMPRESARIAL_2026_10', '2026-10', 'plan', 'empresarial', 'Empresarial (sob consulta)', NULL, NULL, NULL, 1, 'active', 50, NULL
    UNION ALL SELECT 'TOPUP_OPERATIONAL_500_2026_10', '2026-10', 'topup_operational', NULL, '+500 mensagens operacionais', 49.90, 500, NULL, 0, 'active', 60, NULL
    UNION ALL SELECT 'TOPUP_OPERATIONAL_1000_2026_10', '2026-10', 'topup_operational', NULL, '+1.000 mensagens operacionais', 89.90, 1000, NULL, 0, 'active', 70, NULL
    UNION ALL SELECT 'MARKETING_CREDIT_2026_10', '2026-10', 'marketing_unit', NULL, 'Credito de campanha (por mensagem entregue)', 0.55, NULL, 1, 0, 'active', 80, JSON_OBJECT('pack_sizes', JSON_ARRAY(100, 500, 1000, 5000))
    UNION ALL SELECT 'PLAN_LEGACY_STARTER', 'legacy-v1', 'plan', 'starter', 'Starter (legado)', 99.00, 1000, NULL, 0, 'legacy', 900, NULL
    UNION ALL SELECT 'PLAN_LEGACY_GROWTH', 'legacy-v1', 'plan', 'growth', 'Growth (legado)', 249.00, 5000, NULL, 0, 'legacy', 901, NULL
    UNION ALL SELECT 'PLAN_LEGACY_PRO', 'legacy-v1', 'plan', 'pro', 'Pro (legado)', 599.00, 20000, NULL, 0, 'legacy', 902, NULL
    UNION ALL SELECT 'PLAN_LEGACY_ENTERPRISE', 'legacy-v1', 'plan', 'enterprise', 'Enterprise (legado)', 1499.00, 100000, NULL, 0, 'legacy', 903, NULL
    UNION ALL SELECT 'PLAN_LEGACY_ON_DEMAND', 'legacy-v1', 'plan', 'on_demand', 'On demand (legado)', 0.00, NULL, NULL, 0, 'legacy', 904, NULL
) seed
WHERE NOT EXISTS (SELECT 1 FROM billing_catalog_items b WHERE b.code = seed.code);

INSERT INTO meta_rate_cards (provider, version_code, market, currency, category, rate_micros, unit_price, billing_basis, free_allowance, tier_min, effective_from, source_reference, notes, needs_review, active)
SELECT 'meta', 'RATE_BR_2026_10_01', 'BR', 'BRL', seed.category, seed.micros, seed.unit_price, 'per_delivered_message', 0, 0, '2026-10-01',
       'https://developers.facebook.com/docs/whatsapp/pricing/',
       'Valores de negocio preservados do cadastro anterior; validar contra tabela oficial Meta', 1, 1
FROM (
    SELECT 'MARKETING' AS category, 321700 AS micros, 0.321700 AS unit_price
    UNION ALL SELECT 'UTILITY', 35000, 0.035000
    UNION ALL SELECT 'AUTHENTICATION', 35000, 0.035000
    UNION ALL SELECT 'SERVICE', 0, 0.000000
) seed
WHERE NOT EXISTS (
    SELECT 1 FROM meta_rate_cards m
    WHERE m.provider='meta' AND m.market='BR' AND m.currency='BRL' AND m.category=seed.category
      AND m.effective_from='2026-10-01' AND m.tier_min=0
);

INSERT INTO billing_cost_config (config_key, value, description)
SELECT seed.k, seed.v, seed.d FROM (
    SELECT 'target_margin' AS k, 0.300000 AS v, 'Margem de contribuicao alvo (0.30 = 30%)' AS d
    UNION ALL SELECT 'payment_fee_percent', NULL, 'Taxa percentual do processador de pagamento'
    UNION ALL SELECT 'payment_fee_fixed', NULL, 'Taxa fixa por cobranca do processador (BRL)'
    UNION ALL SELECT 'tax_rate', NULL, 'Aliquota estimada de impostos sobre receita'
    UNION ALL SELECT 'ai_cost_per_operational_message', NULL, 'Custo estimado de IA por mensagem operacional (BRL)'
    UNION ALL SELECT 'allocated_platform_cost_per_tenant', NULL, 'Custo de infraestrutura alocado por tenant/mes (BRL, opcional)'
) seed
WHERE NOT EXISTS (SELECT 1 FROM billing_cost_config c WHERE c.config_key = seed.k);

DROP PROCEDURE IF EXISTS atende_add_column_if_missing;
DROP PROCEDURE IF EXISTS atende_add_index_if_missing;
DROP PROCEDURE IF EXISTS atende_drop_index_if_exists;
