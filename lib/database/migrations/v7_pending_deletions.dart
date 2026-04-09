const v7PendingDeletions = '''
CREATE TABLE IF NOT EXISTS pending_deletions (
  id TEXT PRIMARY KEY,
  table_name TEXT NOT NULL,
  record_id TEXT NOT NULL,
  deleted_at TEXT NOT NULL
)
''';
