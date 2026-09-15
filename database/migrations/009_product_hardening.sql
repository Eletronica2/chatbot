-- Product hardening: groups, assignment, quick replies, usage ledger, rate cards, fiscal stubs.
-- Idempotent where practical. Does not drop data.

-- Sessions columns (assignment_mode, assigned_user_id, group_id) are applied
-- idempotently by backend bootstrap (MySQLDatabase.ensure_product_hardening_schema).

CREATE TABLE IF NOT EXISTS conversation_groups (
    id CHAR(36) NOT NULL,
    tenant_id BIGINT UNSIGNED NOT NULL,
    name VARCHAR(120) NOT NULL,
    description VARCHAR(500) NULL,
    is_default TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_conversation_groups_tenant_name (tenant_id, name),
    KEY idx_conversation_groups_tenant_default (tenant_id, is_default),
    CONSTRAINT fk_conversation_groups_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS conversation_group_members (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id BIGINT UNSIGNED NOT NULL,
    group_id CHAR(36) NOT NULL,
    user_id VARCHAR(64) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_group_member (group_id, user_id),
    KEY idx_group_members_tenant_user (tenant_id, user_id),
    CONSTRAINT fk_group_members_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_group_members_group
        FOREIGN KEY (group_id) REFERENCES conversation_groups(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS quick_replies (
    id CHAR(36) NOT NULL,
    tenant_id BIGINT UNSIGNED NOT NULL,
    user_id VARCHAR(64) NOT NULL,
    title VARCHAR(160) NOT NULL,
    shortcut VARCHAR(64) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_quick_replies_owner_shortcut (tenant_id, user_id, shortcut),
    KEY idx_quick_replies_owner (tenant_id, user_id),
    CONSTRAINT fk_quick_replies_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS usage_events (
    id CHAR(36) NOT NULL,
    tenant_id BIGINT UNSIGNED NOT NULL,
    provider_message_id VARCHAR(120) NOT NULL,
    direction VARCHAR(16) NOT NULL DEFAULT 'outgoing',
    category VARCHAR(32) NULL,
    market VARCHAR(16) NOT NULL DEFAULT 'BR',
    event_type VARCHAR(32) NOT NULL DEFAULT 'delivered',
    quantity INT UNSIGNED NOT NULL DEFAULT 1,
    delivered_at DATETIME NULL,
    billing_period CHAR(7) NULL,
    stripe_meter_event_id VARCHAR(120) NULL,
    stripe_status VARCHAR(32) NOT NULL DEFAULT 'pending',
    metadata JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_usage_provider_msg (tenant_id, provider_message_id, event_type),
    KEY idx_usage_tenant_period (tenant_id, billing_period),
    KEY idx_usage_stripe_status (stripe_status),
    CONSTRAINT fk_usage_events_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS meta_rate_cards (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    market VARCHAR(16) NOT NULL,
    currency VARCHAR(8) NOT NULL,
    category VARCHAR(32) NOT NULL,
    rate_micros BIGINT NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE NULL,
    source_reference VARCHAR(255) NULL,
    notes VARCHAR(500) NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_meta_rate (market, currency, category, effective_from),
    KEY idx_meta_rate_lookup (market, category, effective_from)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fiscal_documents (
    id CHAR(36) NOT NULL,
    tenant_id BIGINT UNSIGNED NOT NULL,
    competence CHAR(7) NOT NULL,
    document_number VARCHAR(64) NULL,
    amount_cents INT NOT NULL DEFAULT 0,
    currency VARCHAR(8) NOT NULL DEFAULT 'BRL',
    status VARCHAR(32) NOT NULL DEFAULT 'not_configured',
    issued_at DATETIME NULL,
    download_url VARCHAR(500) NULL,
    provider VARCHAR(64) NULL,
    external_id VARCHAR(120) NULL,
    metadata JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_fiscal_tenant_competence (tenant_id, competence),
    CONSTRAINT fk_fiscal_documents_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed Meta rate card estimates for Brazil (consult Meta docs 2026-09-03).
-- Rates are estimates for UI; Meta billing remains on Meta side.
INSERT INTO meta_rate_cards (market, currency, category, rate_micros, effective_from, effective_to, source_reference, notes)
SELECT 'BR', 'BRL', 'MARKETING', 321700, '2026-07-01', NULL,
       'https://developers.facebook.com/docs/whatsapp/pricing/',
       'Estimativa Meta Brasil — por mensagem entregue'
WHERE NOT EXISTS (
    SELECT 1 FROM meta_rate_cards WHERE market='BR' AND category='MARKETING' AND effective_from='2026-07-01'
);

INSERT INTO meta_rate_cards (market, currency, category, rate_micros, effective_from, effective_to, source_reference, notes)
SELECT 'BR', 'BRL', 'UTILITY', 35000, '2026-07-01', NULL,
       'https://developers.facebook.com/docs/whatsapp/pricing/',
       'Estimativa Meta Brasil — utility; regras de janela 24h podem isentar'
WHERE NOT EXISTS (
    SELECT 1 FROM meta_rate_cards WHERE market='BR' AND category='UTILITY' AND effective_from='2026-07-01'
);

INSERT INTO meta_rate_cards (market, currency, category, rate_micros, effective_from, effective_to, source_reference, notes)
SELECT 'BR', 'BRL', 'AUTHENTICATION', 35000, '2026-07-01', NULL,
       'https://developers.facebook.com/docs/whatsapp/pricing/',
       'Estimativa Meta Brasil — authentication'
WHERE NOT EXISTS (
    SELECT 1 FROM meta_rate_cards WHERE market='BR' AND category='AUTHENTICATION' AND effective_from='2026-07-01'
);

INSERT INTO meta_rate_cards (market, currency, category, rate_micros, effective_from, effective_to, source_reference, notes)
SELECT 'BR', 'BRL', 'SERVICE', 0, '2026-07-01', '2026-09-30',
       'https://developers.facebook.com/docs/whatsapp/pricing/',
       'Service free until 2026-09-30 per Meta announced changes; verify official card'
WHERE NOT EXISTS (
    SELECT 1 FROM meta_rate_cards WHERE market='BR' AND category='SERVICE' AND effective_from='2026-07-01'
);

-- Ensure default group "Geral" per tenant (idempotent)
INSERT INTO conversation_groups (id, tenant_id, name, description, is_default)
SELECT UUID(), t.id, 'Geral', 'Grupo padrão de atendimento', 1
FROM tenants t
WHERE NOT EXISTS (
    SELECT 1 FROM conversation_groups g WHERE g.tenant_id = t.id AND g.is_default = 1
);

-- Backfill sessions without group to tenant default group
UPDATE sessions s
INNER JOIN tenants t ON t.id = s.tenant_id
INNER JOIN conversation_groups g ON g.tenant_id = t.id AND g.is_default = 1
SET s.group_id = g.id,
    s.assignment_mode = COALESCE(NULLIF(s.assignment_mode, ''), 'ai')
WHERE s.group_id IS NULL;
