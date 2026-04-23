# MisBolos — Registro de desarrollo

## Descripción
App de gestión de bolos (actuaciones de DJ), clientes y facturas. Desarrollada en Flutter para macOS con soporte futuro para móvil.

## Stack técnico
- **Framework:** Flutter 3.x / Dart 3.x
- **Estado:** Riverpod 2.x (AsyncNotifierProvider)
- **Navegación:** GoRouter con ShellRoute (**5 pestañas**)
- **BD local:** SQLite (sqflite + sqflite_common_ffi para desktop)
- **Cloud:** Supabase (sincronización de datos)
- **Google APIs:** googleapis + googleapis_auth (Calendar v3, Drive v3)
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
- Sincronización de clients, gigs, invoices (solo datos oficiales)
- Cola `pending_deletions` para borrados offline

### Configuración OAuth (macOS)
- **Proyecto Google Cloud:** "MisBolos"
- **Tipo de credencial:** Desktop (OAuth 2.0)
- **Client ID:** `744196169382-knr1najrpc3muiim38k3epg6rdmdpuhj.apps.googleusercontent.com`
- **Client Secret:** almacenado en `.env` y hardcodeado en el servicio
- **Scopes:** Calendar, Drive, email, profile
- **Test user:** `jesus.cintasmu@gmail.com` (añadido en OAuth consent screen)

### Google Calendar
- **Servicio:** `lib/services/google_calendar_service.dart`
- Crea calendario "MisBolos" automáticamente
- Sincroniza TODOS los bolos (facturables y no facturables)
- Eventos coloreados por estado
- Lookup por `extendedProperties` (gig ID)

### Google Drive (macOS)
- Upload de PDFs de facturas a `MisBolos/Facturas`
- Backup de base de datos a `MisBolos/Backups`
- (**Nota:** `google_drive_service.dart` eliminado; la funcionalidad de Drive se gestiona a través del `SupabaseService` en el flujo multiplataforma)

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
│   ├── database_helper.dart           # SQLite init + migraciones (versión 13)
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
│       └── v13_assets_iva.dart        # importe_con_iva, iva_rate, iva_amount en assets
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

## Pendientes prioritarios

### 1) ✅ Módulo de gastos (implementado — v10)
- Migración `v10` con tabla `expenses`
- Pantallas: lista con filtros, formulario (nuevo/editar), detalle
- Adjuntar justificante (PDF/foto) con `file_picker` + `image_picker`
- Conectado al resumen financiero: desglose por categoría e IVA soportado
- Rutas: `/expense/new`, `/expense/edit/:id`, `/expense/:id`

### 2) ✅ Módulo de inversiones/inmovilizado (implementado — v11)
- Migración `v11` con tabla `assets`
- Pantallas: lista, formulario, detalle con tabla de amortización trimestral
- Separación IVA / base imponible (v13): `importe_con_iva`, `iva_rate`, `iva_amount`
- Dropdown IVA 21/10/4/0%; preview amortización con base sin IVA
- Cálculo de cuota anual/trimestral/mensual y valor contable
- Rutas: `/asset/new`, `/asset/edit/:id`, `/asset/:id`

### 3) ✅ Sincronización Supabase para gastos e inversiones (implementado — v12)
- Columnas `cloud_id` en `expenses` y `assets`
- `SyncProvider`: `uploadToCloud()` genera UUID y lo guarda, `downloadFromCloud()` hace upsert por `cloud_id`
- RLS en Supabase: cada usuario solo ve sus datos

### 4) ✅ Reorganización NavBar 7 → 5 tabs (commit 482b173)
- ANTES: Inicio | Calendario | Clientes | Facturas | Gastos | Inversiones | Perfil
- DESPUÉS: Inicio | Agenda | **Finanzas** | Clientes | Perfil
- `FinanzasScreen`: `DefaultTabController(3)` con TabBar interno Facturas/Gastos/Inversiones
- FAB del Dashboard expandido a 4 acciones: bolo / cliente / gasto / inversión

### 5) Asistente IA
- Integrar asistente sobre la arquitectura actual de repositorios
- Enviar contexto real de negocio a Claude API
- Enfocar como diferencial académico del proyecto

### 6) Envío de facturas por email
- Reutilizar el PDF de factura ya generado
- Implementar envío por correo con Brevo
- Completar el flujo final post-generación de factura

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
