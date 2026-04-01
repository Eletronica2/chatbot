SET NAMES utf8mb4;
SET time_zone = '+00:00';

CREATE TABLE IF NOT EXISTS tenants (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    external_key VARCHAR(120) NULL,
    name VARCHAR(160) NOT NULL,
    email VARCHAR(190) NOT NULL,
    whatsapp_phone_number VARCHAR(32) NULL,
    whatsapp_token TEXT NULL,
    status ENUM('active', 'inactive', 'suspended') NOT NULL DEFAULT 'active',
    plan VARCHAR(50) NOT NULL DEFAULT 'starter',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_tenants_external_key (external_key),
    UNIQUE KEY uq_tenants_email (email),
    KEY idx_tenants_status (status),
    KEY idx_tenants_plan (plan)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS subscriptions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id BIGINT UNSIGNED NOT NULL,
    plan VARCHAR(50) NOT NULL DEFAULT 'starter',
    status ENUM('active', 'trialing', 'past_due', 'canceled', 'inactive') NOT NULL DEFAULT 'active',
    renewal_date DATETIME NOT NULL,
    monthly_message_limit INT UNSIGNED NOT NULL DEFAULT 1000,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_subscriptions_tenant (tenant_id),
    KEY idx_subscriptions_tenant_status (tenant_id, status),
    CONSTRAINT fk_subscriptions_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS tenant_settings (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id BIGINT UNSIGNED NOT NULL,
    ai_enabled TINYINT(1) NOT NULL DEFAULT 1,
    flow_editing_enabled TINYINT(1) NOT NULL DEFAULT 1,
    debug_mode TINYINT(1) NOT NULL DEFAULT 0,
    gemini_model VARCHAR(120) NOT NULL DEFAULT 'gemini-1.5-flash-latest',
    fallback_models JSON NULL,
    available_models JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_tenant_settings_tenant (tenant_id),
    CONSTRAINT fk_tenant_settings_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS users (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id BIGINT UNSIGNED NOT NULL,
    email VARCHAR(190) NOT NULL,
    display_name VARCHAR(160) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'owner',
    status ENUM('active', 'inactive', 'invited') NOT NULL DEFAULT 'active',
    last_login_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_users_email (email),
    KEY idx_users_tenant (tenant_id),
    CONSTRAINT fk_users_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS flows (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id BIGINT UNSIGNED NOT NULL,
    flow_key VARCHAR(120) NOT NULL,
    name VARCHAR(160) NOT NULL,
    description TEXT NULL,
    start_state_key VARCHAR(120) NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_flows_tenant_key (tenant_id, flow_key),
    KEY idx_flows_tenant (tenant_id),
    CONSTRAINT fk_flows_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS flow_states (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id BIGINT UNSIGNED NOT NULL,
    flow_id BIGINT UNSIGNED NOT NULL,
    state_key VARCHAR(120) NOT NULL,
    display_name VARCHAR(160) NOT NULL,
    message TEXT NULL,
    intent_triggers JSON NULL,
    requires_handoff TINYINT(1) NOT NULL DEFAULT 0,
    integration_action VARCHAR(120) NULL,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_flow_states_flow_state (flow_id, state_key),
    KEY idx_flow_states_tenant (tenant_id),
    KEY idx_flow_states_flow (flow_id),
    CONSTRAINT fk_flow_states_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_flow_states_flow
        FOREIGN KEY (flow_id) REFERENCES flows(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS flow_transitions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id BIGINT UNSIGNED NOT NULL,
    flow_id BIGINT UNSIGNED NOT NULL,
    source_state_id BIGINT UNSIGNED NOT NULL,
    target_state_id BIGINT UNSIGNED NOT NULL,
    transition_type ENUM('contains', 'equals', 'regex', 'always', 'intent') NOT NULL DEFAULT 'contains',
    match_value VARCHAR(255) NULL,
    option_label VARCHAR(160) NULL,
    option_value VARCHAR(160) NULL,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_flow_transitions_tenant (tenant_id),
    KEY idx_flow_transitions_source (source_state_id),
    KEY idx_flow_transitions_target (target_state_id),
    CONSTRAINT fk_flow_transitions_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_flow_transitions_flow
        FOREIGN KEY (flow_id) REFERENCES flows(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_flow_transitions_source
        FOREIGN KEY (source_state_id) REFERENCES flow_states(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_flow_transitions_target
        FOREIGN KEY (target_state_id) REFERENCES flow_states(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sessions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    session_id CHAR(36) NOT NULL,
    tenant_id BIGINT UNSIGNED NOT NULL,
    phone_number VARCHAR(32) NOT NULL,
    phone_number_id VARCHAR(64) NULL,
    display_phone_number VARCHAR(32) NULL,
    active_flow VARCHAR(120) NULL,
    current_state VARCHAR(120) NULL,
    last_flow VARCHAR(120) NULL,
    detected_intent VARCHAR(120) NULL,
    conversation_history JSON NULL,
    session_state JSON NULL,
    context JSON NULL,
    last_interaction DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_sessions_tenant_phone (tenant_id, phone_number),
    UNIQUE KEY uq_sessions_session_id (session_id),
    KEY idx_sessions_tenant (tenant_id),
    KEY idx_sessions_last_interaction (tenant_id, last_interaction),
    CONSTRAINT fk_sessions_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS messages (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id BIGINT UNSIGNED NOT NULL,
    session_id BIGINT UNSIGNED NOT NULL,
    direction ENUM('incoming', 'outgoing') NOT NULL DEFAULT 'incoming',
    role ENUM('user', 'assistant', 'system') NOT NULL DEFAULT 'user',
    content TEXT NOT NULL,
    source VARCHAR(32) NOT NULL DEFAULT 'gateway',
    external_message_id VARCHAR(120) NULL,
    phone_number_id VARCHAR(64) NULL,
    metadata JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_messages_tenant (tenant_id),
    KEY idx_messages_external (tenant_id, external_message_id),
    KEY idx_messages_session_created (session_id, created_at),
    CONSTRAINT fk_messages_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_messages_session
        FOREIGN KEY (session_id) REFERENCES sessions(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS conversation_logs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id BIGINT UNSIGNED NOT NULL,
    session_id BIGINT UNSIGNED NULL,
    phone_number VARCHAR(32) NOT NULL,
    user_message TEXT NOT NULL,
    bot_response TEXT NOT NULL,
    flow_used VARCHAR(120) NULL,
    state VARCHAR(120) NULL,
    source VARCHAR(32) NOT NULL DEFAULT 'flow',
    detected_intent VARCHAR(120) NULL,
    response_time_ms INT UNSIGNED NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_conversation_logs_tenant (tenant_id),
    KEY idx_conversation_logs_tenant_created (tenant_id, created_at),
    KEY idx_conversation_logs_phone (tenant_id, phone_number),
    CONSTRAINT fk_conversation_logs_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_conversation_logs_session
        FOREIGN KEY (session_id) REFERENCES sessions(id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
