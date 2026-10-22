-- Per-tenant automatic reply control. Additive; the default 'on' preserves current behavior for every tenant.
-- 'off' stores inbound and hands it to a human; 'allowlist' replies automatically only to listed senders.
DELIMITER $$
DROP PROCEDURE IF EXISTS atende_012_add_column_if_missing $$
CREATE PROCEDURE atende_012_add_column_if_missing(IN p_column VARCHAR(64), IN p_ddl TEXT)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tenant_settings' AND COLUMN_NAME = p_column
    ) THEN
        SET @atende_012_ddl = p_ddl;
        PREPARE atende_012_stmt FROM @atende_012_ddl;
        EXECUTE atende_012_stmt;
        DEALLOCATE PREPARE atende_012_stmt;
    END IF;
END $$
DELIMITER ;

CALL atende_012_add_column_if_missing('auto_reply_mode',
    'ALTER TABLE tenant_settings ADD COLUMN auto_reply_mode VARCHAR(16) NOT NULL DEFAULT ''on''');
CALL atende_012_add_column_if_missing('auto_reply_allowlist',
    'ALTER TABLE tenant_settings ADD COLUMN auto_reply_allowlist JSON NULL');
DROP PROCEDURE IF EXISTS atende_012_add_column_if_missing;
