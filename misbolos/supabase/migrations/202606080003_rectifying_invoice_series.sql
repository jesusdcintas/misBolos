ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS rectification_reason_type TEXT,
  ADD COLUMN IF NOT EXISTS rectification_reason_description TEXT;

DROP INDEX IF EXISTS public.idx_invoices_numero_user_year;
DROP INDEX IF EXISTS public.idx_invoices_year_numero;
DROP INDEX IF EXISTS public.idx_invoices_year_type_numero;

CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_year_type_numero
  ON public.invoices (
    user_id,
    (EXTRACT(YEAR FROM fecha_emision)),
    invoice_type,
    numero
  )
  WHERE deleted_at IS NULL;

NOTIFY pgrst, 'reload schema';
