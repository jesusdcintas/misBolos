ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS invoice_last_reminder_sent_at TIMESTAMPTZ;

UPDATE user_settings
SET invoice_last_reminder_sent_at = COALESCE(
  invoice_last_reminder_sent_at,
  last_invoice_reminder_email_sent_at
);
