const String v35DriveQueueInvoiceIdempotency = '''
ALTER TABLE invoices ADD COLUMN drive_uploaded_at TEXT;
ALTER TABLE invoices ADD COLUMN drive_sync_status TEXT NOT NULL DEFAULT 'pending';

DELETE FROM drive_sync_queue
WHERE rowid NOT IN (
  SELECT MAX(rowid)
  FROM drive_sync_queue
  GROUP BY entity_type, entity_id
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_drive_sync_queue_entity_unique
  ON drive_sync_queue(entity_type, entity_id);
''';
