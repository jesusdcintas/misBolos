-- Ensure invoice numbers are unique only inside the same user + fiscal year.
-- This removes known older global uniqueness indexes before creating the
-- per-year constraint used by the app.

DROP INDEX IF EXISTS public.idx_invoices_numero;
DROP INDEX IF EXISTS public.idx_invoices_numero_unique;
DROP INDEX IF EXISTS public.idx_invoices_numero_user;
DROP INDEX IF EXISTS public.idx_invoices_numero_user_year;

CREATE UNIQUE INDEX idx_invoices_numero_user_year
  ON public.invoices (
    user_id,
    (EXTRACT(YEAR FROM fecha_emision)),
    numero
  );

NOTIFY pgrst, 'reload schema';
