const String v31ExpensesAssetsSoftDelete = '''
ALTER TABLE expenses ADD COLUMN deleted_at TEXT;
ALTER TABLE assets ADD COLUMN deleted_at TEXT;

CREATE INDEX IF NOT EXISTS idx_expenses_deleted_at ON expenses(deleted_at);
CREATE INDEX IF NOT EXISTS idx_assets_deleted_at ON assets(deleted_at);
''';
