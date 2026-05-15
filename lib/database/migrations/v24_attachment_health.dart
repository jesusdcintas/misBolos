const String v24AttachmentHealth = '''
ALTER TABLE expenses ADD COLUMN attachment_status TEXT NOT NULL DEFAULT 'pending_upload';
ALTER TABLE expenses ADD COLUMN attachment_error TEXT;
ALTER TABLE expenses ADD COLUMN attachment_original_path TEXT;

ALTER TABLE assets ADD COLUMN attachment_status TEXT NOT NULL DEFAULT 'pending_upload';
ALTER TABLE assets ADD COLUMN attachment_error TEXT;
ALTER TABLE assets ADD COLUMN attachment_original_path TEXT;
''';
