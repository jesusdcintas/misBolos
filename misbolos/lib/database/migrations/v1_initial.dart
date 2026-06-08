const String v1InitialMigration = '''
CREATE TABLE IF NOT EXISTS clients (
  id TEXT PRIMARY KEY,
  nombre TEXT NOT NULL,
  cif_nif TEXT DEFAULT '',
  direccion TEXT DEFAULT '',
  ciudad TEXT DEFAULT '',
  codigo_postal TEXT DEFAULT '',
  email TEXT,
  telefono TEXT,
  whatsapp_phone TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS gigs (
  id TEXT PRIMARY KEY,
  fecha TEXT NOT NULL,
  client_id TEXT NOT NULL,
  notas TEXT,
  cachet REAL,
  facturable INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'confirmado',
  invoice_id TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (client_id) REFERENCES clients(id)
);

CREATE TABLE IF NOT EXISTS invoices (
  id TEXT PRIMARY KEY,
  numero INTEGER NOT NULL,
  fecha TEXT NOT NULL,
  client_id TEXT NOT NULL,
  gig_id TEXT NOT NULL,
  items TEXT NOT NULL,
  subtotal REAL NOT NULL,
  iva_rate REAL NOT NULL DEFAULT 0.21,
  iva_amount REAL NOT NULL,
  total REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'borrador',
  created_at TEXT NOT NULL,
  FOREIGN KEY (client_id) REFERENCES clients(id),
  FOREIGN KEY (gig_id) REFERENCES gigs(id)
);

CREATE TABLE IF NOT EXISTS app_settings (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  logo_path TEXT DEFAULT '',
  emisor_nombre TEXT DEFAULT '',
  emisor_nif TEXT DEFAULT '',
  emisor_direccion TEXT DEFAULT '',
  emisor_ciudad TEXT DEFAULT '',
  emisor_email TEXT DEFAULT '',
  emisor_telefono TEXT DEFAULT '',
  iban TEXT DEFAULT '',
  iva_default REAL DEFAULT 0.21,
  notificaciones_activas INTEGER DEFAULT 1,
  dias_recordatorio INTEGER DEFAULT 7
);

INSERT OR IGNORE INTO app_settings (id) VALUES (1);
''';
