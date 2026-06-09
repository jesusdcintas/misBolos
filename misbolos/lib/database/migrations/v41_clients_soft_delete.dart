const String v41ClientsSoftDelete = '''
ALTER TABLE clients ADD COLUMN deleted_at TEXT;

CREATE INDEX IF NOT EXISTS idx_clients_deleted_at ON clients(deleted_at);
''';
