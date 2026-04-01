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
