ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS in_app_invoice_reminders_enabled BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS email_invoice_reminders_enabled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS invoice_reminder_frequency TEXT NOT NULL DEFAULT 'weekly',
  ADD COLUMN IF NOT EXISTS last_invoice_reminder_email_sent_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS invoice_reminder_email_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_email TEXT NOT NULL,
  subject TEXT NOT NULL,
  invoice_ids TEXT[] NOT NULL DEFAULT '{}',
  invoice_count INTEGER NOT NULL DEFAULT 0,
  total_pending NUMERIC NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'sent',
  error_message TEXT,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoice_reminder_email_logs_user_created
  ON invoice_reminder_email_logs(user_id, created_at DESC);

ALTER TABLE invoice_reminder_email_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own invoice reminder email logs"
  ON invoice_reminder_email_logs;

CREATE POLICY "Users can view their own invoice reminder email logs"
  ON invoice_reminder_email_logs FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service can insert invoice reminder email logs"
  ON invoice_reminder_email_logs;

CREATE POLICY "Service can insert invoice reminder email logs"
  ON invoice_reminder_email_logs FOR INSERT
  WITH CHECK (auth.uid() = user_id);
