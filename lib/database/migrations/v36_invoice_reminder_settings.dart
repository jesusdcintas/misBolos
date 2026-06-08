const String v36InvoiceReminderSettings = '''
ALTER TABLE app_settings ADD COLUMN email_invoice_reminders_enabled INTEGER NOT NULL DEFAULT 0;
ALTER TABLE app_settings ADD COLUMN invoice_reminder_frequency TEXT NOT NULL DEFAULT 'weekly';
ALTER TABLE app_settings ADD COLUMN last_invoice_reminder_email_sent_at TEXT;
''';
