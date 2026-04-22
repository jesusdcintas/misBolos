/// v12: añade cloud_id (UUID) a expenses y assets para sincronización con Supabase.
/// La columna es nullable; se genera en el primer upload.
const String v12CloudIds = '''
ALTER TABLE expenses ADD COLUMN cloud_id TEXT;
ALTER TABLE assets ADD COLUMN cloud_id TEXT
''';
