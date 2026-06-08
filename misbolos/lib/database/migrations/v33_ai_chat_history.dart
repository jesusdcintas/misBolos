const String v33AiChatHistory = '''
CREATE TABLE IF NOT EXISTS ai_chats (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS ai_chat_messages (
  id TEXT PRIMARY KEY,
  chat_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TEXT NOT NULL,
  metadata_json TEXT NULL,
  FOREIGN KEY(chat_id) REFERENCES ai_chats(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ai_chats_active_updated
ON ai_chats(is_active, updated_at);

CREATE INDEX IF NOT EXISTS idx_ai_chat_messages_chat_created
ON ai_chat_messages(chat_id, created_at);
''';
