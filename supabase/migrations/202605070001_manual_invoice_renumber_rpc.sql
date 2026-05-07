ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS number_locked BOOLEAN NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS public.invoice_number_changes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  old_number INTEGER,
  new_number INTEGER NOT NULL CHECK (new_number > 0),
  source TEXT NOT NULL CHECK (source IN ('create_invoice', 'manual_renumber')),
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoice_number_changes_invoice
  ON public.invoice_number_changes(invoice_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_invoice_number_changes_user_source
  ON public.invoice_number_changes(user_id, source, created_at DESC);

CREATE OR REPLACE FUNCTION public.audit_invoice_number_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.numero::INTEGER <= 0 THEN
    RAISE EXCEPTION 'No se puede crear una factura con número temporal';
  END IF;

  INSERT INTO public.invoice_number_changes (
    invoice_id,
    user_id,
    old_number,
    new_number,
    source,
    reason
  )
  VALUES (
    NEW.id,
    NEW.user_id,
    NULL,
    NEW.numero::INTEGER,
    'create_invoice',
    'invoice_insert'
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_invoice_number_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_source TEXT := current_setting('app.invoice_number_change_source', true);
BEGIN
  IF NEW.numero IS DISTINCT FROM OLD.numero THEN
    IF v_source <> 'manual_renumber' THEN
      RAISE EXCEPTION 'Cambio de número no autorizado para factura %', OLD.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS invoices_audit_number_insert ON public.invoices;
CREATE TRIGGER invoices_audit_number_insert
  AFTER INSERT ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.audit_invoice_number_insert();

DROP TRIGGER IF EXISTS invoices_guard_number_update ON public.invoices;
CREATE TRIGGER invoices_guard_number_update
  BEFORE UPDATE OF numero ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.guard_invoice_number_update();

DROP FUNCTION IF EXISTS public.renumber_invoices_manually(INTEGER, JSONB);

CREATE OR REPLACE FUNCTION public.renumber_invoices_manually(
  p_fiscal_year INTEGER,
  p_changes JSONB,
  p_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_total INTEGER;
  v_distinct_numbers INTEGER;
  v_target_rows INTEGER;
  v_collision TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_changes IS NULL OR jsonb_typeof(p_changes) <> 'array' THEN
    RAISE EXCEPTION 'Formato de cambios inválido';
  END IF;

  SELECT COUNT(*)
  INTO v_total
  FROM jsonb_array_elements(p_changes) AS change;

  IF v_total = 0 THEN
    RAISE EXCEPTION 'No hay facturas para reenumerar';
  END IF;

  SELECT COUNT(DISTINCT (change->>'numero')::INTEGER)
  INTO v_distinct_numbers
  FROM jsonb_array_elements(p_changes) AS change;

  IF v_distinct_numbers <> v_total THEN
    RAISE EXCEPTION 'Hay números duplicados en la nueva numeración';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_changes) AS change
    WHERE (change->>'numero')::INTEGER <= 0
  ) THEN
    RAISE EXCEPTION 'Todos los nuevos números deben ser positivos';
  END IF;

  SELECT COUNT(*)
  INTO v_target_rows
  FROM public.invoices invoice
  JOIN jsonb_array_elements(p_changes) AS change
    ON invoice.id = (change->>'id')::UUID
  WHERE invoice.user_id = v_user_id
    AND invoice.deleted_at IS NULL
    AND EXTRACT(YEAR FROM invoice.fecha_emision)::INTEGER = p_fiscal_year;

  IF v_target_rows <> v_total THEN
    RAISE EXCEPTION 'Todas las facturas deben pertenecer al usuario y año fiscal indicados';
  END IF;

  SELECT invoice.numero
  INTO v_collision
  FROM public.invoices invoice
  WHERE invoice.user_id = v_user_id
    AND invoice.deleted_at IS NULL
    AND EXTRACT(YEAR FROM invoice.fecha_emision)::INTEGER = p_fiscal_year
    AND invoice.numero IN (
      SELECT (change->>'numero')::TEXT
      FROM jsonb_array_elements(p_changes) AS change
    )
    AND invoice.id NOT IN (
      SELECT (change->>'id')::UUID
      FROM jsonb_array_elements(p_changes) AS change
    )
  LIMIT 1;

  IF v_collision IS NOT NULL THEN
    RAISE EXCEPTION 'El número % choca con una factura fuera del lote', v_collision;
  END IF;

  PERFORM set_config('app.invoice_number_change_source', 'manual_renumber', true);

  DROP TABLE IF EXISTS pg_temp.invoice_renumber_before;
  CREATE TEMP TABLE invoice_renumber_before ON COMMIT DROP AS
  SELECT
    invoice.id,
    invoice.numero::INTEGER AS old_number,
    (change->>'numero')::INTEGER AS new_number,
    row_number() OVER () AS row_index
  FROM public.invoices invoice
  JOIN jsonb_array_elements(p_changes) AS change
    ON invoice.id = (change->>'id')::UUID
  WHERE invoice.user_id = v_user_id;

  UPDATE public.invoices invoice
  SET
    numero = (-9000000 - invoice_renumber_before.row_index)::TEXT,
    number_locked = false,
    updated_at = now()
  FROM invoice_renumber_before
  WHERE invoice.id = invoice_renumber_before.id
    AND invoice.user_id = v_user_id;

  UPDATE public.invoices invoice
  SET
    numero = invoice_renumber_before.new_number::TEXT,
    number_locked = true,
    updated_at = now()
  FROM invoice_renumber_before
  WHERE invoice.id = invoice_renumber_before.id
    AND invoice.user_id = v_user_id;

  INSERT INTO public.invoice_number_changes (
    invoice_id,
    user_id,
    old_number,
    new_number,
    source,
    reason
  )
  SELECT
    invoice_renumber_before.id,
    v_user_id,
    invoice_renumber_before.old_number,
    invoice_renumber_before.new_number,
    'manual_renumber',
    p_reason
  FROM invoice_renumber_before
  WHERE invoice_renumber_before.old_number <> invoice_renumber_before.new_number;
END;
$$;

GRANT EXECUTE ON FUNCTION public.renumber_invoices_manually(INTEGER, JSONB, TEXT)
  TO authenticated;

ALTER TABLE public.invoice_number_changes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS invoice_number_changes_select_own
  ON public.invoice_number_changes;

CREATE POLICY invoice_number_changes_select_own
  ON public.invoice_number_changes
  FOR SELECT
  USING (auth.uid() = user_id);

NOTIFY pgrst, 'reload schema';
