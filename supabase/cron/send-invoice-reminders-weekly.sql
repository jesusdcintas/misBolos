-- Scheduled job helper for Supabase Dashboard or SQL editor.
-- Replace the secret value below with the same one used in:
--   INVOICE_REMINDER_CRON_SECRET=mb_invoice_reminder_2026_clave_larga_random
-- Then schedule the function weekly, for example Mondays at 08:00.

select cron.schedule(
  'send-invoice-reminders-weekly',
  '0 8 * * 1',
  $$
  select
    net.http_post(
      url := 'https://utkuxjplwggfndnaqqir.supabase.co/functions/v1/send-invoice-reminders',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', '__SET_IN_SUPABASE__'
      ),
      body := '{"force": true}'::jsonb
    ) as request_id;
  $$
);
