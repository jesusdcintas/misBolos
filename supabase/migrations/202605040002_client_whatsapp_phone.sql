ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS whatsapp_phone TEXT;

UPDATE clients
SET whatsapp_phone = telefono
WHERE whatsapp_phone IS NULL
  AND telefono IS NOT NULL
  AND btrim(telefono) <> '';
