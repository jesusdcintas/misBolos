const String v38Verifactu = '''
ALTER TABLE app_settings ADD COLUMN verifactu_enabled INTEGER NOT NULL DEFAULT 0;

ALTER TABLE invoices ADD COLUMN is_fiscally_issued INTEGER NOT NULL DEFAULT 0;
ALTER TABLE invoices ADD COLUMN fiscal_hash TEXT;
ALTER TABLE invoices ADD COLUMN fiscal_record_id TEXT;
ALTER TABLE invoices ADD COLUMN invoice_type TEXT NOT NULL DEFAULT 'normal';
ALTER TABLE invoices ADD COLUMN rectifies_invoice_id TEXT;
ALTER TABLE invoices ADD COLUMN rectification_reason TEXT;
ALTER TABLE invoices ADD COLUMN rectification_type TEXT;
ALTER TABLE invoices ADD COLUMN original_invoice_number TEXT;
ALTER TABLE invoices ADD COLUMN original_invoice_date TEXT;

CREATE TABLE IF NOT EXISTS invoice_fiscal_records (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  invoice_id TEXT NOT NULL,
  record_type TEXT NOT NULL CHECK (record_type IN ('issue', 'rectification', 'cancellation')),
  invoice_number TEXT NOT NULL,
  invoice_series TEXT NOT NULL DEFAULT '',
  issued_at TEXT NOT NULL,
  previous_hash TEXT,
  current_hash TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  aeat_status TEXT NOT NULL DEFAULT 'not_sent'
    CHECK (aeat_status IN ('not_sent', 'pending', 'sent', 'accepted', 'rejected', 'error')),
  aeat_error TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (invoice_id) REFERENCES invoices(id)
);

CREATE INDEX IF NOT EXISTS idx_invoice_fiscal_records_invoice
  ON invoice_fiscal_records(invoice_id);

CREATE INDEX IF NOT EXISTS idx_invoice_fiscal_records_user_series
  ON invoice_fiscal_records(user_id, invoice_series, created_at);
''';
