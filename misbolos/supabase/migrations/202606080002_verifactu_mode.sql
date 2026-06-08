ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS verifactu_enabled BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS is_fiscally_issued BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS fiscal_hash TEXT,
  ADD COLUMN IF NOT EXISTS fiscal_record_id UUID,
  ADD COLUMN IF NOT EXISTS invoice_type TEXT NOT NULL DEFAULT 'normal'
    CHECK (invoice_type IN ('normal', 'rectifying')),
  ADD COLUMN IF NOT EXISTS rectifies_invoice_id UUID REFERENCES public.invoices(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS rectification_reason TEXT,
  ADD COLUMN IF NOT EXISTS rectification_type TEXT
    CHECK (rectification_type IS NULL OR rectification_type IN ('substitution', 'difference')),
  ADD COLUMN IF NOT EXISTS original_invoice_number TEXT,
  ADD COLUMN IF NOT EXISTS original_invoice_date DATE;

CREATE TABLE IF NOT EXISTS public.invoice_fiscal_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
  record_type TEXT NOT NULL CHECK (record_type IN ('issue', 'rectification', 'cancellation')),
  invoice_number TEXT NOT NULL,
  invoice_series TEXT NOT NULL DEFAULT '',
  issued_at TIMESTAMPTZ NOT NULL,
  previous_hash TEXT,
  current_hash TEXT NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  aeat_status TEXT NOT NULL DEFAULT 'not_sent'
    CHECK (aeat_status IN ('not_sent', 'pending', 'sent', 'accepted', 'rejected', 'error')),
  aeat_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.invoice_fiscal_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own invoice fiscal records"
  ON public.invoice_fiscal_records;
CREATE POLICY "Users can view their own invoice fiscal records"
  ON public.invoice_fiscal_records FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own invoice fiscal records"
  ON public.invoice_fiscal_records;
CREATE POLICY "Users can insert their own invoice fiscal records"
  ON public.invoice_fiscal_records FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own invoice fiscal records"
  ON public.invoice_fiscal_records;
CREATE POLICY "Users can update their own invoice fiscal records"
  ON public.invoice_fiscal_records FOR UPDATE
  USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_invoice_fiscal_records_user_series_created
  ON public.invoice_fiscal_records(user_id, invoice_series, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_invoice_fiscal_records_invoice
  ON public.invoice_fiscal_records(invoice_id);
