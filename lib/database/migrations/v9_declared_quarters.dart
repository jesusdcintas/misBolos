const v9DeclaredQuarters = '''
CREATE TABLE IF NOT EXISTS declared_quarters (
  id TEXT PRIMARY KEY,
  year INTEGER NOT NULL,
  quarter INTEGER NOT NULL,
  declared_at TEXT NOT NULL,
  iva_amount REAL
);
''';
