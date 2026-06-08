# Plan Maestro de Implementación y Checklist - MisBolos

Fecha de consolidación: 2026-05-22  
Fuentes consolidadas:
- `docs/google_drive_integration_plan.md`
- `docs/supabase_auth_login_plan.md`
- `PENDIENTE_IA.md`

---

## 1) Estado global por bloques

### 1.1 Google Drive
- Estado: **completado en alcance actual**.
- Resumen:
  - Integración Drive operativa con selección de carpeta raíz.
  - Estructura idempotente y sincronización documental.
  - Cola de errores/reintentos y reparación de adjuntos legacy.
  - Backup/restore JSON descartado por producto.

Checklist consolidada:
- [x] Conexión/desconexión Google Drive.
- [x] Selección de carpeta raíz por `folderId`.
- [x] Creación idempotente de estructura.
- [x] Subida de facturas.
- [x] Subida de gastos/inversiones con adjuntos.
- [x] Cola de sync con reintentos y limpieza de inválidos.
- [x] Resumen de estado en UI.
- [x] Pruebas E2E principales entre dispositivos y Drive.
- [x] Backup JSON retirado del alcance.
- [x] Restauración JSON retirada del alcance.

Pendiente real:
- [ ] Solo mejoras opcionales futuras (no bloqueantes) si producto lo requiere.

---

### 1.2 Auth Supabase (login principal)
- Estado: **completado** (email/password + Google + sesión persistente).
- Resumen:
  - Rutas públicas/privadas con guardas.
  - Login/registro/recuperación/reset.
  - Login Google (móvil + macOS/OAuth).
  - Logout en Perfil con limpieza de estado y datos locales del usuario.

Checklist consolidada:
- [x] `AuthController` implementado.
- [x] Pantallas: login, registro, forgot/reset.
- [x] Sesión persistente en arranque (`currentSession`).
- [x] Guardas de GoRouter.
- [x] Logout en Perfil.
- [x] Limpieza de estado al logout.
- [x] `user_id` en modelo/sync y políticas RLS por `auth.uid()`.
- [x] Soporte offline con sesión persistida.
- [x] Google login con manejo de errores.

Pendiente real:
- [ ] Ninguno bloqueante en el alcance original del plan.

---

### 1.3 IA (Groq / extracción y redacción)
- Estado: **base implementada + pendientes de exposición en UI diaria**.

Checklist consolidada:
- [x] Arquitectura segura (`Flutter -> Edge Function -> Groq`).
- [x] Secretos fuera de cliente.
- [x] Extracción IA de gastos/inversiones (texto/PDF/imagen).
- [x] Revisión manual antes de guardar.
- [x] Postprocesado determinista de inversiones.
- [x] Retirada del cambio de concepto masivo.
- [x] Base de asistente IA operativo con acciones estructuradas, preview y confirmación antes de ejecutar.
- [x] Persistencia local del historial del asistente IA con chats activos y mensajes en SQLite.

Pendiente inmediato:
- [x] Reestructuración final UI de Perfil para unificar sesión MisBolos + Google + Drive + Calendar sin redundancias.
- [ ] Ampliar asistente IA con redacción diaria para WhatsApp/email/resúmenes en flujos de uso.

Pendiente opcional:
- [ ] Trazabilidad funcional mínima (logs sin datos sensibles).
- [ ] Ajuste fino de prompts con más casos reales.
- [ ] Mejora OCR en escaneos complejos si reaparece necesidad.

---

## 2) Backlog único priorizado

### Prioridad alta
- [x] Cerrar unificación UX de Perfil (cuentas y conexiones, sin estados duplicados).
- [x] Terminar homogeneidad visual dark/light donde aún hay inconsistencias de contraste.
- [x] Validar migraciones SQLite locales pendientes en instalaciones antiguas (caso `deleted_at`).
- [ ] Implementar integración VeriFactu (cumplimiento y envío fiscal según normativa vigente).

### Prioridad media
- [ ] Exponer funcionalidades IA clave en pantallas de trabajo diario.
- [ ] Repaso final de textos de error y estados de sincronización.
- [x] Corregir bug de teclado iOS en `Perfil > Datos de facturación` (foco estable + scroll visible sobre teclado).

### Prioridad baja
- [ ] Mejoras opcionales de observabilidad IA y OCR.

---

## 3) Decisiones vigentes
- Drive es archivo documental, no fuente principal de verdad.
- No se borra/mueve/renombra contenido existente en Drive fuera del alcance seguro definido.
- Backup/restauración JSON fuera de alcance actual.
- En logout se limpia estado y datos locales del usuario para evitar mezcla entre sesiones.
- Proveedor de email transaccional cerrado: `Brevo` (secrets activos: `BREVO_API_KEY` e `INVOICE_FROM_EMAIL`).

---

## 4) Criterio de cierre del plan maestro
El plan se considerará cerrado cuando:
- [x] La unificación de Perfil quede finalizada y validada visual/funcionalmente.
- [ ] No haya incidencias abiertas de sincronización entre dispositivos.
- [x] Se complete pasada final de QA en dark/light para Finanzas, Agenda/Bolos y Perfil.
- [x] En iPhone, campos inferiores de facturación se editan sin cierre automático del teclado.
