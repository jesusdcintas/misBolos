const String v4AddIrpf = '''
ALTER TABLE invoices ADD COLUMN irpf_rate REAL DEFAULT 0.0;
ALTER TABLE invoices ADD COLUMN irpf_amount REAL DEFAULT 0.0
''';
