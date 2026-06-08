const String v10Expenses = '''
CREATE TABLE IF NOT EXISTS expenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT,
  fecha TEXT NOT NULL,
  concepto TEXT NOT NULL,
  proveedor TEXT,
  importe_base REAL NOT NULL,
  iva_rate REAL NOT NULL DEFAULT 21.0,
  iva_amount REAL NOT NULL,
  total REAL NOT NULL,
  categoria TEXT NOT NULL DEFAULT 'otros',
  es_deducible INTEGER NOT NULL DEFAULT 1,
  porcentaje_deduccion REAL NOT NULL DEFAULT 100.0,
  documento_path TEXT,
  notas TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)
''';
