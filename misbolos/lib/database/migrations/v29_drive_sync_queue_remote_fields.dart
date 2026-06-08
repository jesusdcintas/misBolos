const String v29DriveSyncQueueRemoteFields = '''
ALTER TABLE drive_sync_queue ADD COLUMN drive_file_id TEXT;
ALTER TABLE drive_sync_queue ADD COLUMN remote_folder_id TEXT;

CREATE INDEX IF NOT EXISTS idx_drive_sync_queue_remote
  ON drive_sync_queue(entity_type, entity_id, drive_file_id);
''';
