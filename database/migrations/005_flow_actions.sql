-- Migration 005: Flow Actions catalog
-- Stores reusable actions (send_image, send_link, http_request, delay, send_document)
-- per tenant. The `config` column holds a JSON payload specific to each action_type.

CREATE TABLE IF NOT EXISTS flow_actions (
    id           BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id    BIGINT UNSIGNED  NOT NULL,
    name         VARCHAR(120)     NOT NULL,
    action_type  ENUM(
        'send_image',
        'send_link',
        'http_request',
        'delay',
        'send_document'
    )                             NOT NULL,
    config       LONGTEXT         NOT NULL DEFAULT ('{}'),
    created_at   TIMESTAMP        DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP        DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_flow_actions_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX IF NOT EXISTS idx_flow_actions_tenant ON flow_actions (tenant_id);
