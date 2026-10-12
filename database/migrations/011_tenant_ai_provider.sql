-- IA-02: per-tenant provider selection; additive defaults preserve current Gemini behavior.
DELIMITER $$
DROP PROCEDURE IF EXISTS atende_ia02_add_column_if_missing $$
CREATE PROCEDURE atende_ia02_add_column_if_missing(IN p_column VARCHAR(64), IN p_ddl TEXT)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tenant_settings' AND COLUMN_NAME = p_column
    ) THEN
        SET @ia02_ddl = p_ddl;
        PREPARE ia02_stmt FROM @ia02_ddl;
        EXECUTE ia02_stmt;
        DEALLOCATE PREPARE ia02_stmt;
    END IF;
END $$
DELIMITER ;

CALL atende_ia02_add_column_if_missing('ai_provider',
    'ALTER TABLE tenant_settings ADD COLUMN ai_provider VARCHAR(20) NOT NULL DEFAULT ''gemini''');
CALL atende_ia02_add_column_if_missing('local_ai_enabled',
    'ALTER TABLE tenant_settings ADD COLUMN local_ai_enabled TINYINT(1) NOT NULL DEFAULT 0');
DROP PROCEDURE IF EXISTS atende_ia02_add_column_if_missing;
