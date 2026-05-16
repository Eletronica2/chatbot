-- Migration 006: Leads capture
-- Stores prospects captured by the public signup form on the landing page.
-- Used by the internal team to follow up and close deals.

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
