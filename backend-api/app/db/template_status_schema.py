"""Persisted WhatsApp template status (webhook + Graph sync)."""
from __future__ import annotations


def apply(cursor, *, ensure_index) -> None:
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS whatsapp_template_status (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            tenant_id BIGINT UNSIGNED NOT NULL,
            account_key VARCHAR(120) NOT NULL,
            template_id VARCHAR(64) NULL,
            template_name VARCHAR(512) NOT NULL,
            language VARCHAR(32) NOT NULL DEFAULT 'pt_BR',
            graph_status VARCHAR(32) NULL,
            webhook_status VARCHAR(32) NULL,
            rejected_reason VARCHAR(512) NULL,
            graph_synced_at BIGINT UNSIGNED NULL,
            webhook_event_at BIGINT UNSIGNED NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uq_tpl_status_tenant_tpl (tenant_id, account_key, template_name, language),
            KEY idx_tpl_status_watch (tenant_id, account_key, updated_at),
            CONSTRAINT fk_tpl_status_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS whatsapp_template_webhook_dedup (
            dedupe_key VARCHAR(190) NOT NULL,
            tenant_id BIGINT UNSIGNED NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (dedupe_key),
            KEY idx_tpl_webhook_dedup_tenant (tenant_id, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        """
    )