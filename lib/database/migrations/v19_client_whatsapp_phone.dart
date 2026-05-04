const String v19ClientWhatsappPhone = '''
ALTER TABLE clients ADD COLUMN whatsapp_phone TEXT;

UPDATE clients
SET whatsapp_phone = telefono
WHERE whatsapp_phone IS NULL
  AND telefono IS NOT NULL
  AND TRIM(telefono) != ''
''';
