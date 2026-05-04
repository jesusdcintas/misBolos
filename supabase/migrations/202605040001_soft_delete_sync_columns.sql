ALTER TABLE gigs
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

UPDATE gigs
SET updated_at = COALESCE(updated_at, created_at, now())
WHERE updated_at IS NULL;

UPDATE invoices
SET updated_at = COALESCE(updated_at, created_at, now())
WHERE updated_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_gigs_deleted_at
  ON gigs(deleted_at);

CREATE INDEX IF NOT EXISTS idx_invoices_deleted_at
  ON invoices(deleted_at);

DROP INDEX IF EXISTS idx_invoices_numero_user_year;

CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_numero_user_year
  ON invoices(user_id, (EXTRACT(YEAR FROM fecha_emision)), numero)
  WHERE deleted_at IS NULL;
