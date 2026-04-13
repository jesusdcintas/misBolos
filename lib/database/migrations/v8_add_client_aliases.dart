const v8AddClientAliases = '''
ALTER TABLE clients ADD COLUMN aliases TEXT DEFAULT '[]'
''';
