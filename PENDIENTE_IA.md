# Pendiente IA - MisBolos

Fecha de actualización: 2026-05-19

## Ya implementado

- Arquitectura segura de IA: `Flutter -> Supabase Edge Function -> Groq`.
- Claves de IA fuera de Flutter (`GROQ_API_KEY` en secretos de Supabase).
- Edge Function `groq-assistant` para:
  - redacción (`chat`, `whatsapp`, `email`, `summarize`)
  - extracción (`extract_expense`, `extract_investment`)
- Extracción IA de Gastos e Inversiones desde:
  - texto manual
  - PDF con texto
  - imagen/foto (galería y cámara)
- Envío de imágenes a IA con `input_type=image`, compresión/redimensión y base64.
- Postprocesado determinista en extracción de inversiones (validación de importes y reglas de categoría/amortización).
- Pantalla de revisión manual antes de guardar (no guardado automático por IA).

## Pendiente inmediato

- Reestructurar UI de Perfil para unificar y simplificar conexiones:
  - cuenta principal (sesión MisBolos)
  - cuenta de Google
  - Google Drive
  - Google Calendar
  - eliminar redundancias y dejar flujo más intuitivo/consistente.
- Exponer en UI de uso diario:
  - redacción IA de WhatsApp para facturas/clientes
  - redacción IA de email para facturas
  - resúmenes IA (cliente, bolo, factura)

## Completado reciente

- Retirada la opción "Cambio de concepto masivo" en Facturas.
- QA E2E en dos dispositivos completado para casos principales.
- Arreglado compartir por WhatsApp dentro del alcance acordado.

## Pendiente opcional

- Añadir trazabilidad funcional mínima de IA (logs sin datos sensibles) para depuración.
- Ajustar prompts/reglas con ejemplos reales adicionales.
- Mejorar OCR para PDFs escaneados complejos solo si aparece nueva casuística.
