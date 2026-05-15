const String v27AttachmentFileMetadata = '''
ALTER TABLE expenses ADD COLUMN attachment_original_name TEXT;
ALTER TABLE expenses ADD COLUMN attachment_stored_name TEXT;
ALTER TABLE expenses ADD COLUMN attachment_mime_type TEXT;

ALTER TABLE assets ADD COLUMN attachment_original_name TEXT;
ALTER TABLE assets ADD COLUMN attachment_stored_name TEXT;
ALTER TABLE assets ADD COLUMN attachment_mime_type TEXT;
''';

