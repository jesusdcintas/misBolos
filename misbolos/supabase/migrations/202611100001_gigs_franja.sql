-- Franja del día que ocupa cada bolo.
-- Admite null a propósito: los bolos creados antes de esta columna se tratan
-- como "todo el día" en la app, pero el null se conserva.
ALTER TABLE gigs
  ADD COLUMN IF NOT EXISTS franja TEXT;

ALTER TABLE gigs
  DROP CONSTRAINT IF EXISTS gigs_franja_check;

ALTER TABLE gigs
  ADD CONSTRAINT gigs_franja_check
  CHECK (franja IS NULL OR franja IN ('tarde', 'noche', 'dia_completo'));
