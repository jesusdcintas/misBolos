ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS drive_file_id TEXT,
  ADD COLUMN IF NOT EXISTS drive_file_url TEXT,
  ADD COLUMN IF NOT EXISTS drive_synced_at TIMESTAMPTZ;

ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS drive_file_id TEXT,
  ADD COLUMN IF NOT EXISTS drive_file_url TEXT,
  ADD COLUMN IF NOT EXISTS drive_synced_at TIMESTAMPTZ;

ALTER TABLE assets
  ADD COLUMN IF NOT EXISTS drive_file_id TEXT,
  ADD COLUMN IF NOT EXISTS drive_file_url TEXT,
  ADD COLUMN IF NOT EXISTS drive_synced_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_invoices_drive_file_id
  ON invoices(drive_file_id);

CREATE INDEX IF NOT EXISTS idx_expenses_drive_file_id
  ON expenses(drive_file_id);

CREATE INDEX IF NOT EXISTS idx_assets_drive_file_id
  ON assets(drive_file_id);
