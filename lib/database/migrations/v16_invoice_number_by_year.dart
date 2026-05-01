const String v16InvoiceNumberByYear = '''
CREATE TABLE IF NOT EXISTS invoices_v16 (
  id TEXT PRIMARY KEY,
  numero INTEGER NOT NULL,
  fecha TEXT NOT NULL,
  client_id TEXT NOT NULL,
  gig_id TEXT NOT NULL,
  items TEXT NOT NULL,
  subtotal REAL NOT NULL,
  iva_rate REAL NOT NULL DEFAULT 0.21,
  iva_amount REAL NOT NULL,
  irpf_rate REAL DEFAULT 0.0,
  irpf_amount REAL DEFAULT 0.0,
  total REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'borrador',
  created_at TEXT NOT NULL,
  FOREIGN KEY (client_id) REFERENCES clients(id),
  FOREIGN KEY (gig_id) REFERENCES gigs(id)
);

INSERT OR REPLACE INTO invoices_v16 (
  id,
  numero,
  fecha,
  client_id,
  gig_id,
  items,
  subtotal,
  iva_rate,
  iva_amount,
  irpf_rate,
  irpf_amount,
  total,
  status,
  created_at
)
SELECT
  id,
  numero,
  fecha,
  client_id,
  gig_id,
  items,
  subtotal,
  iva_rate,
  iva_amount,
  COALESCE(irpf_rate, 0.0),
  COALESCE(irpf_amount, 0.0),
  total,
  status,
  created_at
FROM invoices;

DROP TABLE invoices;

ALTER TABLE invoices_v16 RENAME TO invoices;

CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_year_numero
  ON invoices(strftime('%Y', fecha), numero);

CREATE INDEX IF NOT EXISTS idx_invoices_fecha
  ON invoices(fecha);

CREATE INDEX IF NOT EXISTS idx_invoices_client_id
  ON invoices(client_id);

CREATE INDEX IF NOT EXISTS idx_invoices_status
  ON invoices(status)
''';
