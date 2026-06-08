const String v11Assets = '''
  CREATE TABLE IF NOT EXISTS assets (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id              TEXT,
    descripcion          TEXT NOT NULL,
    fecha_compra         TEXT NOT NULL,
    importe_total        REAL NOT NULL,
    valor_residual       REAL NOT NULL DEFAULT 0.0,
    vida_util_anos       INTEGER NOT NULL,
    metodo_amortizacion  TEXT NOT NULL DEFAULT 'lineal',
    categoria            TEXT NOT NULL DEFAULT 'otros',
    documento_path       TEXT,
    notas                TEXT,
    activo               INTEGER NOT NULL DEFAULT 1,
    synced               INTEGER NOT NULL DEFAULT 0,
    created_at           TEXT NOT NULL
  )
''';
