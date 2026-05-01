-- Make invoice numbers unique per fiscal year instead of globally per user.
-- This keeps all existing rows and only changes uniqueness rules.

DROP INDEX IF EXISTS public.idx_invoices_numero_user;

CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_numero_user_year
  ON public.invoices (
    user_id,
    (EXTRACT(YEAR FROM fecha_emision)),
    numero
  );

NOTIFY pgrst, 'reload schema';
