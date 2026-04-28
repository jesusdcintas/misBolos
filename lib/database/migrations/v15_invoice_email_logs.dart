const String v15InvoiceEmailLogs = '''
CREATE TABLE IF NOT EXISTS invoice_email_logs (
  id TEXT PRIMARY KEY,
  invoice_id TEXT NOT NULL,
  client_id TEXT NOT NULL,
  recipient_email TEXT NOT NULL,
  provider TEXT NOT NULL,
  subject TEXT NOT NULL,
  status TEXT NOT NULL,
  error_message TEXT,
  sent_at TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_invoice_email_logs_invoice
  ON invoice_email_logs(invoice_id);

CREATE INDEX IF NOT EXISTS idx_invoice_email_logs_created_at
  ON invoice_email_logs(created_at)
''';
