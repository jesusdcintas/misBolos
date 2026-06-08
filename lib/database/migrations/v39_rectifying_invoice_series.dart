const String v39RectifyingInvoiceSeries = '''
ALTER TABLE invoices ADD COLUMN rectification_reason_type TEXT;
ALTER TABLE invoices ADD COLUMN rectification_reason_description TEXT;

DROP INDEX IF EXISTS idx_invoices_year_numero;
DROP INDEX IF EXISTS idx_invoices_numero_user_year;
DROP INDEX IF EXISTS idx_invoices_year_type_numero;

CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_year_type_numero
  ON invoices(
    CAST(strftime('%Y', fecha) AS INTEGER),
    invoice_type,
    numero
  )
  WHERE deleted_at IS NULL;
''';
