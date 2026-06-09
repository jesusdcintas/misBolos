# MisBolos — Registro de desarrollo

Este documento funciona como bitácora técnica del proyecto: stack, rutas,
migraciones, integraciones, incidencias resueltas y estructura interna.

La descripción funcional completa del producto está en
[PROYECTO.md](PROYECTO.md).

## Descripción
App de gestión de bolos (actuaciones de DJ), clientes y facturas. Desarrollada en Flutter para macOS con soporte futuro para móvil.

## Stack técnico
- **Framework:** Flutter 3.x / Dart 3.x
- **Estado:** Riverpod 2.x (AsyncNotifierProvider)
- **Navegación:** GoRouter con ShellRoute (**5 pestañas**)
- **BD local:** SQLite (sqflite + sqflite_common_ffi para desktop)
- **Cloud:** Supabase (sincronización de datos)
- **Google APIs:** googleapis + googleapis_auth (Calendar v3)
- **PDF:** pdf + printing
- **Gráficas:** fl_chart
- **Calendario:** table_calendar

## Estructura de navegación

### Pestañas principales (ShellRoute) — 5 tabs (reorganizado en abdefcd)
| Pestaña    | Ruta         | Descripción                                              |
|------------|--------------|----------------------------------------------------------|
| Inicio     | /            | Dashboard con resumen, estadísticas y FAB expandible (4 acciones) |
| Agenda     | /calendar    | Vista calendario con bolos                               |
| Finanzas   | /finanzas    | TabBar interno: Facturas / Gastos / Inversiones          |
| Clientes   | /clients     | Lista y gestión de clientes                              |
| Perfil     | /profile     | Cuenta Google, logo, datos emisor                        |

### Rutas modales (fuera del ShellRoute)
| Ruta                      | Descripción                          |
|---------------------------|--------------------------------------|
| `/settings`               | Ajustes (IVA, notificaciones, etc.)  |
| `/stats`                  | Estadísticas                         |
| `/financial`              | Resumen financiero                   |
| `/gig/new`                | Nuevo bolo                           |
| `/gig/edit/:id`           | Editar bolo                          |
| `/gig/:id`                | Detalle de bolo                      |
| `/client/new`             | Nuevo cliente                        |
| `/client/edit/:id`        | Editar cliente                       |
| `/client/:id`             | Detalle de cliente                   |
| `/invoice/:id`            | Detalle de factura                   |
| `/invoice/preview/:id`    | Preview PDF de factura               |
| `/invoice/edit/:id`       | Editar factura                       |
| `/invoice/new/:gigId`     | Nueva factura desde bolo             |
| `/expense/new`            | Nuevo gasto                          |
| `/expense/edit/:id`       | Editar gasto                         |
| `/expense/:id`            | Detalle de gasto                     |
| `/asset/new`              | Nueva inversión                      |
| `/asset/edit/:id`         | Editar inversión                     |
| `/asset/:id`              | Detalle de inversión                 |

## Base de datos — Migraciones

### v1 (inicial)
- Tablas: `clients`, `gigs`, `invoices`, `invoice_items`, `app_settings`
- Campos base para todos los modelos

### v2
- `app_settings`: añadidos `emisor_provincia`, `emisor_codigo_postal`

### v3
- `clients`: añadidos `provincia`, `alias`

### v4
- `invoices`: añadidos `irpf_rate`, `irpf_amount` (REAL, default 0.0)

### v5
- `app_settings`: añadido `logo_size` (REAL, default 80)

### v6
- `app_settings`: añadido `pdf_theme` (TEXT, default `'clasico'`)

### v7
- Nueva tabla `pending_deletions` (id, table_name, record_id, deleted_at) — cola de borrados pendientes de sincronizar

### v8
- `clients`: añadido `aliases` (TEXT JSON array, default `'[]'`)

### v9
- Nueva tabla `declared_quarters` (id, year, quarter, declared_at, iva_amount) — trimestres de IVA declarados

### v10
- Nueva tabla `expenses` (id, user_id, fecha, concepto, proveedor, importe_base, iva_rate, iva_amount, total, categoria, es_deducible, porcentaje_deduccion, documento_path, notas, synced, created_at)

### v11
- Nueva tabla `assets` (id, user_id, descripcion, fecha_compra, importe_total, valor_residual, vida_util_anos, metodo_amortizacion, categoria, documento_path, notas, activo, synced, created_at)
- Modelo con cálculos de amortización: `cuotaAnual`, `cuotaMensual`, `cuotaTrimestral`, `valorContable`, `anosTranscurridos`
- Provider `assetAmortizacionTrimestreProvider` para calcular cuota de un trimestre concreto

### v12
- `expenses`: añadida columna `cloud_id TEXT` (UUID Supabase para sync)
- `assets`: añadida columna `cloud_id TEXT` (UUID Supabase para sync)
- Estrategia: int AUTOINCREMENT local + cloud_id nullable generado en primer upload

### v13
- `assets`: añadidas columnas `importe_con_iva REAL DEFAULT 0.0`, `iva_rate REAL DEFAULT 21.0`, `iva_amount REAL DEFAULT 0.0`
- El campo `importe_total` pasa a representar la **base imponible sin IVA** (amortizable)
- El IVA se deduce en el trimestre de compra (modelo 303); la base se amortiza por años (modelo 130)

### v14
- Nueva tabla `app_events` para trazabilidad local de acciones relevantes
- Índices por entidad (`entity_type`, `entity_id`) y fecha de creación
- Primeros eventos registrados: creación/edición/borrado de bolos y facturas,
  cambios de estado, enlace bolo-factura y generación de PDF de factura

### v15
- Nueva tabla `invoice_email_logs` para registrar intentos de envío de factura
  por email: destinatario, proveedor, asunto, estado, error y fecha de envío

## Integración Google / Auth

### Estrategia dual por plataforma
| Plataforma       | Servicio                      | Paquete             |
|------------------|-------------------------------|---------------------|
| macOS (desktop)  | `google_auth_service.dart`    | `googleapis_auth`   |
| iOS / Android    | `platform_auth_service.dart`  | `google_sign_in` + Supabase |

### macOS — googleapis_auth
- **Flujo:** `clientViaUserConsent` → abre navegador → callback en localhost
- **Servicio:** `lib/services/google_auth_service.dart` (singleton)
- **Provider:** `googleAuthProvider` (StateNotifierProvider)

### iOS/Android — PlatformAuthService
- **Servicio:** `lib/services/platform_auth_service.dart` (singleton)
- Usa `google_sign_in` para obtener ID token + access token
- Autentica en Supabase con `signInWithIdToken`
- `isSignedIn` delega en `SupabaseService.isAuthenticated` en macOS

### Supabase
- **Servicio:** `lib/services/supabase_service.dart` (singleton)
- Inicializado con URL + anon key desde `AppSettings`
- RLS: `auth.uid() = user_id` — cada usuario solo ve sus datos
- Sincronización de clients, gigs, invoices, gastos e inversiones
- Cola `pending_deletions` para borrados offline

### Configuración OAuth (macOS)
- **Proyecto Google Cloud:** "MisBolos"
- **Tipo de credencial:** Desktop (OAuth 2.0)
- **Client ID:** `744196169382-knr1najrpc3muiim38k3epg6rdmdpuhj.apps.googleusercontent.com`
- **Client Secret:** almacenado en `.env` y hardcodeado en el servicio
- **Scopes:** Calendar, email, profile
- **Test user:** `jesus.cintasmu@gmail.com` (añadido en OAuth consent screen)

### Google Calendar
- **Servicio:** `lib/services/google_calendar_service.dart`
- Crea calendario "MisBolos" automáticamente
- Sincroniza TODOS los bolos (facturables y no facturables)
- Eventos coloreados por estado
- Lookup por `extendedProperties` (gig ID)

### Sincronización cloud
- La sincronización y el almacenamiento cloud se apoyan en Supabase y Google
  Calendar.

## Configuración macOS

### Info.plist
- `CFBundleURLTypes` con URL scheme para OAuth redirect:
  `com.googleusercontent.apps.744196169382-knr1najrpc3muiim38k3epg6rdmdpuhj`

### Entitlements (Debug + Release)
- `com.apple.security.app-sandbox`: true
- `com.apple.security.network.client`: true
- `com.apple.security.network.server`: true (solo debug)
- `com.apple.security.cs.allow-jit`: true (solo debug)
- `com.apple.security.files.user-selected.read-only`: true (para image_picker)

## Problemas resueltos

### 1. Pantalla negra en macOS
- **Causa:** sqflite no funciona en desktop sin FFI
- **Solución:** Añadir `sqflite_common_ffi` y condicionar en `main.dart`

### 2. Google Sign-In crash (NSException)
- **Causa:** `google_sign_in` necesita clientId en desktop + URL scheme en Info.plist
- **Solución:** Se acabó reemplazando `google_sign_in` por `googleapis_auth`

### 3. `client_secret is missing`
- **Causa:** `google_sign_in` en macOS no soporta client_secret requerido por OAuth
- **Solución:** Migrar a `googleapis_auth` con `clientViaUserConsent`

### 4. 403 access_denied en OAuth
- **Causa:** Email no estaba como test user en OAuth consent screen
- **Solución:** Añadir email en Google Cloud Console → OAuth consent screen → Test users

### 5. LocaleDataException en calendario
- **Causa:** Faltaba `initializeDateFormatting('es_ES')` antes de usar `table_calendar`
- **Solución:** Llamar en `main()` antes de `runApp`

### 6. No MaterialLocalizations found (DatePicker)
- **Causa:** `MaterialApp` no tenía configurados los delegates de localización
- **Solución:** Añadir `flutter_localizations` al pubspec y configurar `localizationsDelegates` + `supportedLocales` en `MaterialApp`

### 7. image_picker no funciona en macOS
- **Causa:** Faltaba entitlement de acceso a archivos en sandbox
- **Solución:** Añadir `com.apple.security.files.user-selected.read-only` a entitlements

### 8. `table clients has no column named provincia`
- **Causa:** La migración v2 se ejecutó antes de añadir la columna provincia a clients
- **Solución:** Crear migración v3 separada para las columnas nuevas de clients

## Archivos clave

```
lib/
├── main.dart                          # Entry point, FFI init, locale init
├── app.dart                           # MaterialApp + GoRouter (5 tabs ShellRoute)
├── models/
│   ├── app_settings.dart              # Settings del emisor
│   ├── client.dart                    # Cliente con alias, provincia
│   ├── gig.dart                       # Bolo/actuación
│   ├── invoice.dart                   # Factura
│   ├── expense.dart                   # Gasto con IVA y deducibilidad
│   ├── asset.dart                     # Inversión/inmovilizado + amortización + IVA
│   └── pdf_theme.dart                 # Temas de color para PDF (6 temas)
├── database/
│   ├── database_helper.dart           # SQLite init + migraciones (versión 14)
│   └── migrations/
│       ├── v1_initial.dart
│       ├── v2_add_provincia_cp.dart
│       ├── v3_add_client_provincia_alias.dart
│       ├── v4_add_irpf.dart            # irpf_rate, irpf_amount en invoices
│       ├── v5_add_logo_size.dart       # logo_size en app_settings
│       ├── v6_add_pdf_theme.dart       # pdf_theme en app_settings
│       ├── v7_pending_deletions.dart   # tabla pending_deletions
│       ├── v8_add_client_aliases.dart  # aliases JSON en clients
│       ├── v9_declared_quarters.dart  # tabla declared_quarters
│       ├── v10_expenses.dart          # tabla expenses
│       ├── v11_assets.dart            # tabla assets
│       ├── v12_cloud_ids.dart         # cloud_id en expenses y assets
│       ├── v13_assets_iva.dart        # importe_con_iva, iva_rate, iva_amount en assets
│       └── v14_app_events.dart        # tabla app_events para trazabilidad local
├── services/
│   ├── google_auth_service.dart       # Auth macOS (googleapis_auth)
│   ├── platform_auth_service.dart     # Auth iOS/Android (google_sign_in + Supabase)
│   ├── supabase_service.dart          # Sincronización Supabase (clients/gigs/invoices/expenses/assets)
│   ├── google_calendar_service.dart   # Sync con Google Calendar
│   ├── import_service.dart            # Importación desde CSV/Excel
│   ├── pdf_service.dart               # Generación de PDF
│   └── notification_service.dart
├── screens/
│   ├── dashboard/                     # Inicio + FAB 4 acciones
│   ├── calendar/                      # Calendario + detalle de bolo
│   ├── clients/                       # Lista, detalle, formulario
│   ├── finanzas/
│   │   └── finanzas_screen.dart       # TabBar Facturas/Gastos/Inversiones
│   ├── invoices/                      # Lista, detalle, formulario, preview
│   ├── expenses/                      # Lista, detalle, formulario
│   ├── assets/                        # Lista, detalle, formulario con IVA
│   ├── gigs/                          # Lista de bolos
│   ├── profile/                       # Mi Perfil (Google + datos emisor)
│   ├── settings/                      # Ajustes, importación, duplicados
│   └── stats/                         # Estadísticas
├── providers/                         # Riverpod providers
├── repositories/                      # Acceso a BD
└── widgets/                           # Widgets compartidos
```
│   ├── pdf_service.dart               # Generación de PDF
│   └── notification_service.dart
├── screens/
│   ├── dashboard/                     # Inicio
│   ├── calendar/                      # Calendario + detalle de bolo
│   ├── clients/                       # Lista, detalle, formulario
│   ├── gigs/                          # Lista de bolos
│   ├── invoices/                      # Lista, detalle, formulario, preview
│   ├── profile/                       # Mi Perfil (Google + datos emisor)
│   ├── settings/                      # Ajustes, importación, duplicados
│   └── stats/                         # Estadísticas
├── providers/                         # Riverpod providers
├── repositories/                      # Acceso a BD
└── widgets/                           # Widgets compartidos
```

## Pendientes técnicos TFG

Hoja de ruta pendiente tras la revisión arquitectónica del 2026-04-28.
No está implementada todavía. El objetivo es añadir funcionalidades avanzadas
sin romper la arquitectura actual: `models`, `repositories`, `providers`,
`services` y `screens`.

### Observaciones previas
- `stats_provider.dart` concentra demasiada lógica de dashboard, periodos,
  IVA y resumen financiero. Antes de ampliar cálculos fiscales conviene
  extraer un servicio de dominio.
- `FinancialSummaryScreen` ya usa facturas, gastos e inversiones, pero aún no
  existe un modelo fiscal completo que unifique IVA repercutido, IVA soportado,
  amortización y beneficio estimado.
- `Asset` guarda `ivaAmount`, pero también calcula `ivaDeducible` como
  `importeConIva - importeTotal`; hay que definir una fuente canónica.
- `InvoiceStatus.enviada` se usa en la práctica como factura pendiente de
  cobro. Hay que mantenerlo documentado para evitar confusión en UI y lógica.
- No existen logs de envío de factura ni eventos inalterables. Son necesarios
  para email, trazabilidad, asistente IA y modo fiscal estricto.
- `supabase/schema.sql` debe revisarse: aún conserva comentarios/campos antiguos
  sobre bolos en B y nombres históricos.
- No se deben exponer claves de IA/email en cliente Flutter. Deben ir en `.env`
  local o, preferiblemente, en Supabase Edge Functions/secrets.

### Fase 0 — Preparación técnica y trazabilidad (completada)
**Objetivo:** preparar la app para nuevas funcionalidades sin cambiar el
comportamiento visible.
**Estado:** implementada y verificada en código.

**Avance implementado**
- Añadido `PeriodUtils` para rangos de mes/trimestre/año.
- Añadida migración local `v14_app_events`.
- Añadidos `AppEvent` y `AppEventRepository`.
- Registrados eventos básicos en bolos, facturas y generación de PDF.
- Actualizado `supabase/schema.sql` para reflejar bolos en B sincronizables y
  reservar `app_events`.

**Archivos afectados**
- `lib/database/database_helper.dart`
- `lib/providers/stats_provider.dart`
- `supabase/schema.sql`
- `README.md`
- `PROYECTO.md`

**Nuevos archivos**
- `lib/core/utils/period_utils.dart`
- `lib/models/app_event.dart`
- `lib/repositories/app_event_repository.dart`

**Migración**
- `v14_app_events.dart`
- Tabla `app_events`: `id`, `entity_type`, `entity_id`, `event_type`,
  `payload_json`, `created_at`.

**Riesgos**
- Cambios de periodo pueden afectar dashboard y resumen financiero.
- Si se registra demasiado evento, puede crecer la BD local.

**Pruebas**
- Migración desde versión 13.
- Dashboard mes/trimestre/año.
- Sincronización básica Supabase.

**Orden**
1. Extraer utilidades de periodo.
2. Crear tabla local de eventos.
3. Crear repositorio de eventos.
4. Registrar eventos mínimos sin cambiar UI.
5. Actualizar documentación y schema.

### Fase 1 — Resumen financiero mejorado
**Objetivo:** integrar facturas, gastos e inversiones en un cálculo fiscal
coherente.
**Estado:** implementada y verificada en código.

**Avance implementado**
- Añadido modelo `FinancialSummary` con desglose fiscal agregado y por trimestre.
- Añadido `FinancialSummaryService` como lógica pura sin dependencia de UI/BD.
- Añadido `financialSummaryProvider` para combinar facturas, gastos,
  inversiones y bolos en el periodo seleccionado.
- Añadida tarjeta "Fiscalidad estimada" al resumen financiero.
- Exportación PDF ampliada con resumen fiscal estimado.
- Añadidos tests unitarios de cálculo fiscal.

**Cálculos requeridos**
- IVA repercutido.
- IVA soportado en gastos.
- IVA soportado en inversiones.
- IVA a pagar.
- Ingresos oficiales.
- Gastos deducibles.
- Amortización trimestral.
- Beneficio estimado.

**Archivos afectados**
- `lib/models/invoice.dart`
- `lib/models/expense.dart`
- `lib/models/asset.dart`
- `lib/providers/stats_provider.dart`
- `lib/screens/dashboard/financial_summary_screen.dart`
- `lib/services/pdf_service.dart`

**Nuevos archivos**
- `lib/models/financial_summary.dart`
- `lib/services/financial_summary_service.dart`
- `lib/providers/financial_summary_provider.dart`
- `test/financial_summary_service_test.dart`

**Migración**
- No obligatoria inicialmente; se pueden usar campos actuales.

**Riesgos**
- Confundir base imponible, IVA y total con IVA.
- Cambiar importes visibles en dashboard si se modifica el criterio actual.

**Pruebas**
- Facturas borrador/enviadas/pagadas.
- Gastos deducibles, no deducibles y deducibles parcialmente.
- Inversiones dentro/fuera del trimestre.
- Exportación PDF del resumen.
- `flutter analyze`
- `flutter test`

**Orden**
1. Definir modelo `FinancialSummary`. [x]
2. Implementar `FinancialSummaryService` como lógica pura. [x]
3. Crear provider Riverpod. [x]
4. Sustituir cálculos de pantalla por provider. [x]
5. Actualizar PDF. [x]
6. Añadir tests unitarios de cálculo. [x]

### Fase 2 — Envío de facturas por email
**Objetivo:** reutilizar el PDF existente, enviarlo al cliente, registrar log y
cambiar factura a enviada.
**Estado:** completada (cliente + backend desplegado y operativo).

**Avance implementado**
- Añadido log local `invoice_email_logs` con migración v15.
- Añadidos `InvoiceEmailLog`, repositorio y provider.
- Añadido `InvoiceEmailService`, que genera el PDF y llama a una Supabase Edge
  Function sin exponer claves privadas en Flutter.
- Añadida Edge Function `send-invoice-email` preparada para Resend.
- Añadido envío individual desde detalle de factura.
- Añadido envío múltiple desde selección de facturas.
- En envío correcto: registra evento, marca factura como pendiente, repara
  estado del bolo, programa recordatorio y sincroniza Calendar si aplica.
- En fallo: registra log local y evento de error.

**Archivos afectados**
- `lib/services/pdf_service.dart`
- `lib/providers/invoice_provider.dart`
- `lib/screens/invoices/invoice_detail_screen.dart`
- `lib/screens/invoices/invoices_list_screen.dart`
- `lib/services/supabase_service.dart`

**Nuevos archivos**
- `lib/models/invoice_email_log.dart`
- `lib/repositories/invoice_email_log_repository.dart`
- `lib/providers/invoice_email_log_provider.dart`
- `lib/services/invoice_email_service.dart`
- `lib/database/migrations/v15_invoice_email_logs.dart`
- `supabase/functions/send-invoice-email/index.ts`

**Migración**
- `v15_invoice_email_logs.dart`
- Tabla `invoice_email_logs`: `id`, `invoice_id`, `client_id`,
  `recipient_email`, `provider`, `subject`, `status`, `error_message`,
  `sent_at`, `created_at`.

**Proveedor recomendado**
- Resend: opción simple y limpia si hay dominio propio.
- Brevo: buena alternativa con panel completo y enfoque europeo.
- SMTP: solo desde backend seguro, nunca directo desde Flutter.
- Decisión completada: proveedor seleccionado `Brevo`.

**Arquitectura segura**
- Flutter genera o solicita el PDF.
- Flutter llama a una Supabase Edge Function.
- La Edge Function guarda las claves del proveedor en secrets.
- El cliente Flutter nunca contiene API keys privadas.
- Secrets activos para producción con Brevo:
  `BREVO_API_KEY` e `INVOICE_FROM_EMAIL`.

**Cierre**
- Flujo de envío en producción y verificado.
- Estado de factura y log local confirmados tras envío.

**Riesgos**
- Cliente sin email.
- PDF demasiado grande.
- Error parcial: email enviado pero estado no actualizado, o viceversa.
- La función no enviará nada hasta estar desplegada y con secrets configurados.

**Pruebas**
- Envío individual.
- Envío múltiple.
- Cliente sin email.
- Log correcto.
- Estado `InvoiceStatus.enviada` y bolo `facturaEnviada`.
- `flutter analyze`
- `flutter test`

**Orden**
1. Crear log local. [x]
2. Crear servicio abstracto de email. [x]
3. Crear Edge Function de envío. [x]
4. Integrar acción individual. [x]
5. Integrar envío múltiple. [x]
6. Actualizar estado y registrar evento. [x]

### Fase 3 — WhatsApp
**Objetivo:** abrir WhatsApp con mensaje prellenado para cliente usando
`url_launcher`.

**Archivos afectados**
- `lib/screens/invoices/invoice_detail_screen.dart`
- `lib/screens/gigs/gig_detail_screen.dart`
- `lib/models/client.dart`

**Nuevos archivos**
- `lib/services/whatsapp_service.dart`
- `lib/core/utils/phone_formatter.dart`

**Migración**
- No necesaria.

**Regla importante**
- No asumir que se puede adjuntar PDF directamente. Solo se puede incluir enlace
  si existe URL pública o URL firmada.

**Riesgos**
- Teléfonos mal formateados.
- WhatsApp no instalado.
- Diferencias iOS/Android.

**Pruebas**
- Cliente con teléfono válido.
- Cliente sin teléfono.
- Mensaje con datos de bolo/factura.
- Apertura en iOS y Android.

**Orden**
1. Normalizar teléfonos.
2. Construir mensajes prellenados.
3. Abrir `https://wa.me/...`.
4. Añadir fallback si no se puede abrir.
5. Integrar botones en factura/bolo.

### Fase 4 — Extracción automática de gastos con IA
**Objetivo:** subir PDF/foto de factura, extraer datos y prellenar el formulario
de gasto con revisión manual obligatoria.

**Campos a extraer**
- Proveedor.
- Fecha.
- Base imponible.
- IVA.
- Total.
- Categoría sugerida.

**Archivos afectados**
- `lib/screens/expenses/expense_form_screen.dart`
- `lib/providers/expenses_provider.dart`
- `lib/services/supabase_service.dart`

**Nuevos archivos**
- `lib/models/expense_draft.dart`
- `lib/models/expense_extraction_result.dart`
- `lib/services/expense_extraction_service.dart`
- `lib/providers/expense_extraction_provider.dart`

**Migración opcional**
- `v16_expense_extraction_logs.dart`
- Tabla `expense_extraction_logs`: `id`, `source_type`, `document_path`,
  `status`, `extracted_json`, `error_message`, `created_at`.

**Arquitectura segura**
- Flutter selecciona PDF/foto.
- Se sube a Supabase Storage o se manda a una Edge Function.
- La Edge Function llama a la API de IA/OCR con clave secreta.
- La app recibe JSON validado y muestra formulario editable.
- El usuario revisa antes de guardar.

**Riesgos**
- OCR incorrecto.
- Facturas con varios tipos de IVA.
- Documentos sensibles.

**Pruebas**
- PDF simple.
- Foto borrosa.
- IVA 21%, 10%, 0%.
- Corrección manual antes de guardar.

**Orden**
1. Crear modelo draft.
2. Crear Edge Function de extracción.
3. Crear servicio Flutter.
4. Integrar UI de revisión.
5. Guardar como `Expense`.
6. Registrar log de extracción.

### Fase 5 — Asistente IA
**Objetivo:** chat dentro de la app que responda solo con datos reales de
SQLite/Supabase mediante tools internas.

**Casos requeridos**
- "¿Cuánto llevo facturado este trimestre?"
- "¿Quién me debe dinero?"
- "Resume mis ingresos del mes"
- "Qué clientes son más rentables"
- "Prepara una factura para este bolo"

**Archivos afectados**
- `lib/app.dart`
- `lib/providers/*`
- `lib/repositories/*`
- `lib/screens/dashboard/*`
- `lib/screens/invoices/*`

**Nuevos archivos**
- `lib/screens/assistant/assistant_screen.dart`
- `lib/models/assistant_message.dart`
- `lib/models/assistant_action.dart`
- `lib/services/assistant_service.dart`
- `lib/services/assistant_tools.dart`
- `lib/providers/assistant_provider.dart`

**Migración opcional**
- `v17_assistant_logs.dart`
- Tablas `assistant_messages` y `assistant_action_logs`.

**Arquitectura**
- El asistente no debe ser un chatbot genérico.
- Las respuestas se basan en tools deterministas contra repositorios.
- La IA puede redactar, pero no inventar datos.
- Toda acción que modifique datos requiere confirmación explícita.

**Tools internas iniciales**
- `getQuarterRevenue`
- `getDebtors`
- `getMonthlyIncomeSummary`
- `getClientProfitability`
- `prepareInvoiceDraftForGig`

**Riesgos**
- Alucinaciones si se deja responder sin tools.
- Acciones no confirmadas.
- Exposición innecesaria de datos personales.

**Pruebas**
- Preguntas de resumen financiero.
- Listado de deudores.
- Ranking de clientes.
- Preparar factura sin guardarla.
- Confirmación antes de crear/modificar datos.

**Orden**
1. Definir contrato de tools.
2. Implementar tools deterministas.
3. Crear servicio IA con backend seguro.
4. Crear pantalla de chat.
5. Añadir confirmaciones.
6. Tests de tools sin IA.

### Fase 6 — Modo fiscal estricto
**Objetivo:** reservar compatibilidad futura sin implementar todavía el envío
AEAT completo.

**Capacidades futuras**
- QR tributario.
- Hash/huella de factura.
- Registro inalterable.
- Trazabilidad de eventos.
- Posible envío AEAT/API externa.

**Archivos afectados**
- `lib/models/invoice.dart`
- `lib/repositories/invoice_repository.dart`
- `lib/services/pdf_service.dart`
- `lib/screens/invoices/*`

**Nuevos archivos**
- `lib/models/invoice_fiscal_record.dart`
- `lib/models/invoice_event.dart`
- `lib/repositories/invoice_fiscal_record_repository.dart`
- Servicio de modo fiscal estricto

**Migración**
- `v18_invoice_fiscal_fields.dart`
- Campos reservados en `invoices`: `fiscal_status`, `fiscal_hash`,
  `fiscal_qr_payload`, `fiscal_registered_at`, `fiscal_version`,
  `rectifies_invoice_id`.
- Tabla `invoice_fiscal_records`: `id`, `invoice_id`, `event_type`,
  `sequence`, `previous_hash`, `current_hash`, `payload_json`, `qr_payload`,
  `aeat_status`, `aeat_response_json`, `created_at`.

**Riesgos**
- Cambios normativos.
- Edición de facturas ya emitidas.
- Cadena de hash incorrecta.
- Diferencias entre factura ordinaria y rectificativa.

**Pruebas**
- Generación de hash estable.
- Cadena `previous_hash`.
- Evento fiscal por creación/envío/cobro.
- Reserva de QR en PDF sin enviar aún a AEAT.

**Orden**
1. Añadir campos y tabla fiscal.
2. Registrar eventos de factura.
3. Crear servicio de hash local.
4. Preparar payload QR.
5. Añadir advertencias/bloqueos de edición.
6. Documentar el alcance del modo fiscal estricto.

## Variables de entorno (.env)
```
SUPABASE_URL=https://utkuxjplwggfndnaqqir.supabase.co
SUPABASE_ANON_KEY=***
SUPABASE_SERVICE_ROLE_KEY=***
GOOGLE_CLIENT_ID=744196169382-knr1najrpc3muiim38k3epg6rdmdpuhj.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=***
```

## Historial de commits relevantes

| Commit    | Fecha      | Descripción                                                         |
|-----------|------------|---------------------------------------------------------------------|
| 482b173   | 2026-04-23 | nav: reorganizar NavigationBar 7→5 tabs; añadir FinanzasScreen; FAB 4 acciones |
| 32e507f   | 2026-04-23 | feat(assets): separar IVA de base amortizable; migración v13; sync Supabase |
| abdefcd   | 2026-04-23 | fix(forms): replace deprecated DropdownButtonFormField value with initialValue |

## Problemas resueltos (recientes)

### 9. `DropdownButtonFormField.value` deprecado (Flutter 3.33+)
- **Causa:** El parámetro `value:` fue reemplazado por `initialValue:` en Flutter 3.33
- **Solución:** Cambiar `value: _ivaRate` → `initialValue: _ivaRate` en `asset_form_screen.dart`

### 10. Typo spread operator `..[ → ...[`
- **Causa:** Error tipográfico en la lista de `ActionButton` del `ExpandableFAB`
- **Solución:** Corregir el spread operator `...[` en `dashboard_screen.dart`

## Actualización 2026-05-04 — Sync robusta y WhatsApp

### Fase Sync robusta (completada)
- Implementada cola genérica local `sync_queue` para `gig` e `invoice` con
  operaciones `create`, `update`, `delete` y `status_change`.
- Procesador de cola con reintentos, límite de intentos y registro de
  `last_error`.
- Estrategia offline-first: la operación local nunca falla por error de red;
  si Supabase falla, la acción queda pendiente en cola.
- Reintentos automáticos al abrir app, al entrar en secciones clave y al
  relanzar sincronización manual.
- Pull-to-refresh en Agenda y Facturas: primero sube pendientes y después baja
  cambios remotos.
- Compatibilidad mantenida con el botón existente `Sincronizar todo`.
- Añadido indicador UI de pendientes de sincronizar (contador de `sync_queue`).

### Borrados persistentes y conflictos (completado)
- Adoptado `deleted_at` para `gigs` e `invoices` en local y Supabase.
- Política de resolución:
  - `deleted_at` tiene prioridad sobre `updated_at`.
  - si remoto está más nuevo, gana remoto.
  - antes de descargar, se intenta subir primero cambios locales pendientes.
- Evitada “resurrección” de registros borrados al sincronizar entre
  dispositivos.

### Migraciones y schema (completado)
- Supabase:
  - `supabase/migrations/202605040001_soft_delete_sync_columns.sql`
  - `supabase/migrations/202605040002_client_whatsapp_phone.sql`
- SQLite:
  - `v18_sync_queue_soft_delete.dart`
  - `v19_client_whatsapp_phone.dart`
- `schema.sql` actualizado para reflejar `deleted_at`, índices y unicidad de
  facturas ignorando soft-deleted.

### WhatsApp (estado actual)
- Separado teléfono general de cliente y teléfono de WhatsApp:
  `clients.whatsapp_phone`.
- Formulario y detalle de cliente actualizados para editar ambos campos.
- En factura, acción de WhatsApp adaptada para compartir el PDF generado desde
  la app (vía hoja de compartir), con mensaje prellenado.
- En bolo/factura se mantiene normalización de teléfono y fallback cuando no
  hay número válido.

### Validación
- Validación E2E en dos dispositivos: crear/editar/borrar offline y reintento
  al recuperar conexión.
- Instalación en iPhone en modo release verificada durante esta fase.
