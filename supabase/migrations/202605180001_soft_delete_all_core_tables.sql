ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE gigs
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE assets
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

UPDATE clients
SET updated_at = COALESCE(updated_at, created_at, now())
WHERE updated_at IS NULL;

UPDATE gigs
SET updated_at = COALESCE(updated_at, created_at, now())
WHERE updated_at IS NULL;

UPDATE invoices
SET updated_at = COALESCE(updated_at, created_at, now())
WHERE updated_at IS NULL;

UPDATE expenses
SET updated_at = COALESCE(updated_at, created_at, now())
WHERE updated_at IS NULL;

UPDATE assets
SET updated_at = COALESCE(updated_at, created_at, now())
WHERE updated_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_clients_deleted_at
  ON clients(deleted_at);

CREATE INDEX IF NOT EXISTS idx_gigs_deleted_at
  ON gigs(deleted_at);

CREATE INDEX IF NOT EXISTS idx_invoices_deleted_at
  ON invoices(deleted_at);

CREATE INDEX IF NOT EXISTS idx_expenses_deleted_at
  ON expenses(deleted_at);

CREATE INDEX IF NOT EXISTS idx_assets_deleted_at
  ON assets(deleted_at);
