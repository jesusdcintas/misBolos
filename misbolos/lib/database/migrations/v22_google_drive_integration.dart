const String v22GoogleDriveIntegration = '''
ALTER TABLE app_settings ADD COLUMN drive_root_folder_id TEXT;
ALTER TABLE app_settings ADD COLUMN drive_root_folder_name TEXT;
ALTER TABLE app_settings ADD COLUMN drive_account_email TEXT;
ALTER TABLE app_settings ADD COLUMN drive_connected INTEGER NOT NULL DEFAULT 0;
ALTER TABLE app_settings ADD COLUMN last_drive_backup_at TEXT;
ALTER TABLE app_settings ADD COLUMN last_drive_sync_at TEXT;

ALTER TABLE invoices ADD COLUMN drive_file_id TEXT;
ALTER TABLE invoices ADD COLUMN drive_file_url TEXT;
ALTER TABLE invoices ADD COLUMN drive_synced_at TEXT;

ALTER TABLE expenses ADD COLUMN drive_file_id TEXT;
ALTER TABLE expenses ADD COLUMN drive_file_url TEXT;
ALTER TABLE expenses ADD COLUMN drive_synced_at TEXT;

ALTER TABLE assets ADD COLUMN drive_file_id TEXT;
ALTER TABLE assets ADD COLUMN drive_file_url TEXT;
ALTER TABLE assets ADD COLUMN drive_synced_at TEXT;

CREATE TABLE IF NOT EXISTS drive_sync_queue (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  action TEXT NOT NULL,
  local_file_path TEXT,
  target_folder_type TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_drive_sync_queue_entity
  ON drive_sync_queue(entity_type, entity_id);

CREATE INDEX IF NOT EXISTS idx_drive_sync_queue_updated_at
  ON drive_sync_queue(updated_at);
''';
