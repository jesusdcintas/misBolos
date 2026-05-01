const String v17InvoiceNumberUniqueByYear = '''
DROP INDEX IF EXISTS idx_invoices_numero;
DROP INDEX IF EXISTS idx_invoices_numero_unique;
DROP INDEX IF EXISTS idx_invoices_numero_user;
DROP INDEX IF EXISTS idx_invoices_year_numero;

CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_year_numero
  ON invoices(CAST(strftime('%Y', fecha) AS INTEGER), numero)
''';
