const String v2AddProvinciaCp = '''
ALTER TABLE app_settings ADD COLUMN emisor_provincia TEXT DEFAULT '';
ALTER TABLE app_settings ADD COLUMN emisor_codigo_postal TEXT DEFAULT '';
ALTER TABLE clients ADD COLUMN provincia TEXT DEFAULT '';
''';
