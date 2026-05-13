const String v21GigStatusRefactor = '''
UPDATE gigs
SET status = CASE
  WHEN status = 'pendiente' AND facturable = 0 THEN 'confirmado_b'
  WHEN status = 'pendiente' THEN 'confirmado'
  WHEN status = 'factura_generada' THEN 'confirmado'
  WHEN status = 'factura_enviada' THEN 'facturado'
  WHEN status = 'pagado' THEN 'cobrado'
  WHEN status = 'cobrado_en_b' THEN 'cobrado_b'
  ELSE status
END
WHERE status IN (
  'pendiente',
  'factura_generada',
  'factura_enviada',
  'pagado',
  'cobrado_en_b'
);
''';
