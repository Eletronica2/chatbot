-- Migration 007: Flow base snapshots
-- Stores the initial / "base" YAML of each tenant flow so that clients can
-- restore the original automation provided by the platform even after edits.

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
