const String v14AppEvents = '''
CREATE TABLE IF NOT EXISTS app_events (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  payload_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_app_events_entity
  ON app_events(entity_type, entity_id);

CREATE INDEX IF NOT EXISTS idx_app_events_created_at
  ON app_events(created_at)
''';
