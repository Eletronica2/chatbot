"""WhatsApp bulk campaign tables."""
from __future__ import annotations


def apply(cursor, *, ensure_column, ensure_index, fetchone) -> None:
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS whatsapp_campaigns (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            tenant_id BIGINT UNSIGNED NOT NULL,
            campaign_key VARCHAR(64) NOT NULL,
            name VARCHAR(255) NOT NULL,
            status VARCHAR(32) NOT NULL DEFAULT 'draft',
            account_key VARCHAR(64) NULL,
            phone_number_id VARCHAR(64) NULL,
            template_name VARCHAR(512) NOT NULL,
            template_language VARCHAR(32) NOT NULL DEFAULT 'pt_BR',
            template_category VARCHAR(32) NOT NULL DEFAULT 'UTILITY',
            body_variable_keys JSON NULL,
            created_by_user_id VARCHAR(64) NULL,
            confirmed_at DATETIME NULL,
            started_at DATETIME NULL,
            completed_at DATETIME NULL,
            paused_at DATETIME NULL,
            total_recipients INT UNSIGNED NOT NULL DEFAULT 0,
            sent_count INT UNSIGNED NOT NULL DEFAULT 0,
            delivered_count INT UNSIGNED NOT NULL DEFAULT 0,
            read_count INT UNSIGNED NOT NULL DEFAULT 0,
            failed_count INT UNSIGNED NOT NULL DEFAULT 0,
            uncertain_count INT UNSIGNED NOT NULL DEFAULT 0,
            pending_count INT UNSIGNED NOT NULL DEFAULT 0,
            estimate_json JSON NULL,
            meta_cost_estimate_json JSON NULL,
            meta JSON NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uq_campaign_tenant_key (tenant_id, campaign_key),
            KEY idx_campaign_status (tenant_id, status, updated_at),
            CONSTRAINT fk_campaign_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS whatsapp_campaign_recipients (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            tenant_id BIGINT UNSIGNED NOT NULL,
            campaign_id BIGINT UNSIGNED NOT NULL,
            `row_number` INT UNSIGNED NOT NULL,
            phone_e164 VARCHAR(32) NOT NULL,
            body_params JSON NULL,
            consent_ok TINYINT(1) NOT NULL DEFAULT 0,
            status VARCHAR(24) NOT NULL DEFAULT 'pending',
            idempotency_key VARCHAR(128) NOT NULL,
            billing_reservation_id VARCHAR(64) NULL,
            provider_message_id VARCHAR(120) NULL,
            error_code VARCHAR(64) NULL,
            error_message VARCHAR(512) NULL,
            sent_at DATETIME NULL,
            delivered_at DATETIME NULL,
            read_at DATETIME NULL,
            failed_at DATETIME NULL,
            finalized_at DATETIME NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uq_campaign_idempotency (tenant_id, idempotency_key),
            KEY idx_campaign_recipient_status (campaign_id, status),
            CONSTRAINT fk_campaign_recipient_campaign FOREIGN KEY (campaign_id) REFERENCES whatsapp_campaigns(id) ON DELETE CASCADE,
            CONSTRAINT fk_campaign_recipient_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS campaign_recipient_status_events (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            tenant_id BIGINT UNSIGNED NOT NULL,
            recipient_id BIGINT UNSIGNED NOT NULL,
            provider_message_id VARCHAR(120) NOT NULL,
            status VARCHAR(24) NOT NULL,
            error_code VARCHAR(64) NULL,
            received_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            applied TINYINT(1) NOT NULL DEFAULT 0,
            PRIMARY KEY (id),
            UNIQUE KEY uq_campaign_msg_status (tenant_id, provider_message_id, status),
            KEY idx_campaign_status_pending (applied, received_at),
            CONSTRAINT fk_camp_status_recipient FOREIGN KEY (recipient_id)
                REFERENCES whatsapp_campaign_recipients(id) ON DELETE CASCADE,
            CONSTRAINT fk_camp_status_tenant FOREIGN KEY (tenant_id)
                REFERENCES tenants(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        """
    )
    for table, column, ddl in (
        ("whatsapp_campaigns", "delivered_count", "ALTER TABLE whatsapp_campaigns ADD COLUMN delivered_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER sent_count"),
        ("whatsapp_campaigns", "read_count", "ALTER TABLE whatsapp_campaigns ADD COLUMN read_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER delivered_count"),
        ("whatsapp_campaigns", "uncertain_count", "ALTER TABLE whatsapp_campaigns ADD COLUMN uncertain_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER failed_count"),
        ("whatsapp_campaigns", "pending_count", "ALTER TABLE whatsapp_campaigns ADD COLUMN pending_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER uncertain_count"),
        ("whatsapp_campaigns", "meta_cost_estimate_json", "ALTER TABLE whatsapp_campaigns ADD COLUMN meta_cost_estimate_json JSON NULL AFTER estimate_json"),
        ("whatsapp_campaign_recipients", "delivered_at", "ALTER TABLE whatsapp_campaign_recipients ADD COLUMN delivered_at DATETIME NULL AFTER sent_at"),
        ("whatsapp_campaign_recipients", "read_at", "ALTER TABLE whatsapp_campaign_recipients ADD COLUMN read_at DATETIME NULL AFTER delivered_at"),
        ("whatsapp_campaign_recipients", "failed_at", "ALTER TABLE whatsapp_campaign_recipients ADD COLUMN failed_at DATETIME NULL AFTER read_at"),
    ):
        ensure_column(cursor, table=table, column=column, ddl=ddl)
    ensure_index(
        cursor,
        table="whatsapp_campaign_recipients",
        index_name="idx_campaign_wamid",
        ddl="CREATE INDEX idx_campaign_wamid ON whatsapp_campaign_recipients (tenant_id, provider_message_id)",
    )