-- Align remote Supabase `public.invoices` schema with what the app expects.
-- This migration is safe to run multiple times.

-- Ensure invoice issue/amount columns exist (Spanish naming used in supabase/schema.sql)
ALTER TABLE IF EXISTS public.invoices
  ADD COLUMN IF NOT EXISTS fecha_emision date;

ALTER TABLE IF EXISTS public.invoices
  ADD COLUMN IF NOT EXISTS iva_porcentaje real NOT NULL DEFAULT 21;

ALTER TABLE IF EXISTS public.invoices
  ADD COLUMN IF NOT EXISTS iva_importe real NOT NULL DEFAULT 0;

ALTER TABLE IF EXISTS public.invoices
  ADD COLUMN IF NOT EXISTS irpf_porcentaje real NOT NULL DEFAULT 0;

ALTER TABLE IF EXISTS public.invoices
  ADD COLUMN IF NOT EXISTS irpf_importe real NOT NULL DEFAULT 0;

-- Backfill fecha_emision when remote schema used `fecha` or is null.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'invoices'
      AND column_name = 'fecha'
  ) THEN
    UPDATE public.invoices
      SET fecha_emision = COALESCE(fecha_emision, fecha::date)
      WHERE fecha_emision IS NULL;
  END IF;
END $$;

UPDATE public.invoices
  SET fecha_emision = COALESCE(fecha_emision, created_at::date)
  WHERE fecha_emision IS NULL;

-- Notify PostgREST to reload schema cache so new columns are visible immediately.
NOTIFY pgrst, 'reload schema';

