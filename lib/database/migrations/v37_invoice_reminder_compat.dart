const String v37InvoiceReminderCompat = '''
ALTER TABLE app_settings ADD COLUMN invoice_last_reminder_sent_at TEXT;
UPDATE app_settings
SET invoice_last_reminder_sent_at = COALESCE(
  invoice_last_reminder_sent_at,
  last_invoice_reminder_email_sent_at
);
''';
