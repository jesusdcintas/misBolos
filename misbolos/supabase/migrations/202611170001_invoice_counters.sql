-- Número de la siguiente factura, fijado a mano por el usuario.
--
-- Solo guarda lo que se fija a mano: emitir o crear facturas no toca esta
-- tabla. El número siguiente lo calcula la app combinando este valor con el
-- mayor número ya usado entre las facturas no borradas.
--
-- Una fila por usuario, serie y año fiscal.
CREATE TABLE IF NOT EXISTS public.invoice_counters (
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  serie       TEXT        NOT NULL CHECK (serie IN ('F', 'R')),
  fiscal_year INT         NOT NULL CHECK (fiscal_year BETWEEN 2000 AND 2100),
  next_number INT         NOT NULL CHECK (next_number > 0),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, serie, fiscal_year)
);

-- updated_at lo pone siempre el servidor: al fusionar gana el cambio más
-- reciente, y eso solo tiene sentido si las dos fechas salen del mismo reloj.
CREATE OR REPLACE FUNCTION public.set_invoice_counter_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS invoice_counters_set_updated_at ON public.invoice_counters;
CREATE TRIGGER invoice_counters_set_updated_at
  BEFORE INSERT OR UPDATE ON public.invoice_counters
  FOR EACH ROW EXECUTE FUNCTION public.set_invoice_counter_updated_at();

ALTER TABLE public.invoice_counters ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own invoice counters"
  ON public.invoice_counters;
CREATE POLICY "Users can view their own invoice counters"
  ON public.invoice_counters FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own invoice counters"
  ON public.invoice_counters;
CREATE POLICY "Users can insert their own invoice counters"
  ON public.invoice_counters FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own invoice counters"
  ON public.invoice_counters;
CREATE POLICY "Users can update their own invoice counters"
  ON public.invoice_counters FOR UPDATE
  USING (auth.uid() = user_id);

-- Sin política de DELETE a propósito: un contador no se borra desde la app,
-- así que nadie puede reiniciar la numeración desde un dispositivo.
