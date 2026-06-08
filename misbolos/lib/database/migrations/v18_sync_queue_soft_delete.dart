const String v18SyncQueueSoftDelete = '''
ALTER TABLE gigs ADD COLUMN updated_at TEXT;
ALTER TABLE gigs ADD COLUMN deleted_at TEXT;
ALTER TABLE invoices ADD COLUMN updated_at TEXT;
ALTER TABLE invoices ADD COLUMN deleted_at TEXT;

UPDATE gigs
SET updated_at = created_at
WHERE updated_at IS NULL;

UPDATE invoices
SET updated_at = created_at
WHERE updated_at IS NULL;

DROP INDEX IF EXISTS idx_invoices_year_numero;

CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_year_numero
  ON invoices(CAST(strftime('%Y', fecha) AS INTEGER), numero)
  WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS sync_queue (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('gig', 'invoice')),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (
    operation IN ('create', 'update', 'delete', 'status_change')
  ),
  payload_json TEXT NOT NULL DEFAULT '{}',
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sync_queue_pending
  ON sync_queue(entity_type, entity_id, created_at);

CREATE INDEX IF NOT EXISTS idx_sync_queue_updated_at
  ON sync_queue(updated_at)
''';
