USE medilink;

-- Remove duplicates first, then enforce unique medicine names.
DELETE m1
FROM medicines m1
JOIN medicines m2
  ON m1.name = m2.name
 AND m1.medicine_id > m2.medicine_id;

SET @idx_exists := (
  SELECT COUNT(1)
  FROM information_schema.statistics
  WHERE table_schema = DATABASE()
    AND table_name = 'medicines'
    AND index_name = 'uq_medicines_name'
);

SET @idx_sql := IF(
  @idx_exists = 0,
  'ALTER TABLE medicines ADD UNIQUE KEY uq_medicines_name (name)',
  'SELECT 1'
);

PREPARE stmt_idx FROM @idx_sql;
EXECUTE stmt_idx;
DEALLOCATE PREPARE stmt_idx;

-- Keep compatibility with custom medication time slot.
SET @has_custom := (
  SELECT IF(COLUMN_TYPE LIKE '%''custom''%', 1, 0)
  FROM information_schema.columns
  WHERE table_schema = DATABASE()
    AND table_name = 'schedules'
    AND column_name = 'time_slot'
  LIMIT 1
);

SET @slot_sql := IF(
  @has_custom = 0,
  "ALTER TABLE schedules MODIFY COLUMN time_slot ENUM('morning','lunch','dinner','bedtime','custom') NOT NULL",
  'SELECT 1'
);

PREPARE stmt_slot FROM @slot_sql;
EXECUTE stmt_slot;
DEALLOCATE PREPARE stmt_slot;

CREATE TABLE IF NOT EXISTS medicine_sync_state (
  sync_key VARCHAR(64) PRIMARY KEY,
  last_synced_at DATETIME NULL,
  last_status ENUM('idle', 'running', 'success', 'failed') NOT NULL DEFAULT 'idle',
  last_message VARCHAR(255) NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

INSERT INTO medicine_sync_state (sync_key, last_synced_at, last_status, last_message)
VALUES ('drug_api_weekly', NULL, 'idle', 'not-run-yet')
ON DUPLICATE KEY UPDATE
  sync_key = VALUES(sync_key);
