const String v3AddClientProvinciaAlias = '''
ALTER TABLE clients ADD COLUMN provincia TEXT DEFAULT '';
ALTER TABLE clients ADD COLUMN alias TEXT DEFAULT '';
''';
