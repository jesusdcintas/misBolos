const String v28DriveSyncQueueMetadata = '''
ALTER TABLE drive_sync_queue ADD COLUMN document_type TEXT;
ALTER TABLE drive_sync_queue ADD COLUMN file_name TEXT;
ALTER TABLE drive_sync_queue ADD COLUMN mime_type TEXT;
ALTER TABLE drive_sync_queue ADD COLUMN file_size_bytes INTEGER;
ALTER TABLE drive_sync_queue ADD COLUMN file_checksum TEXT;
ALTER TABLE drive_sync_queue ADD COLUMN logical_path TEXT;
ALTER TABLE drive_sync_queue ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE drive_sync_queue ADD COLUMN next_retry_at TEXT;
ALTER TABLE drive_sync_queue ADD COLUMN last_error_code TEXT;

CREATE INDEX IF NOT EXISTS idx_drive_sync_queue_status
  ON drive_sync_queue(sync_status, next_retry_at);
''';
