-- Refactor de estados de gigs:
-- pendiente/factura_generada/factura_enviada/pagado/cobrado_en_b
-- => confirmado/facturado/cobrado/confirmado_b/realizado_b/cobrado_b

UPDATE gigs
SET status = CASE
  WHEN status = 'pendiente' AND facturable = false THEN 'confirmado_b'
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

ALTER TABLE gigs DROP CONSTRAINT IF EXISTS gigs_status_check;

ALTER TABLE gigs
  ADD CONSTRAINT gigs_status_check
  CHECK (status IN (
    'confirmado',
    'facturado',
    'cobrado',
    'confirmado_b',
    'realizado_b',
    'cobrado_b',
    'cancelado'
  ));

ALTER TABLE gigs ALTER COLUMN status SET DEFAULT 'confirmado';
