const String v20InvoiceNumberChanges = '''
ALTER TABLE invoices ADD COLUMN number_locked INTEGER NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS invoice_number_changes (
  id TEXT PRIMARY KEY,
  invoice_id TEXT NOT NULL,
  user_id TEXT,
  old_number INTEGER,
  new_number INTEGER NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('create_invoice', 'manual_renumber')),
  reason TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_invoice_number_changes_invoice
  ON invoice_number_changes(invoice_id, created_at);

CREATE INDEX IF NOT EXISTS idx_invoice_number_changes_source
  ON invoice_number_changes(source, created_at)
''';
