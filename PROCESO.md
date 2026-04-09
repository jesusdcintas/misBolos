# MisBolos — Registro de desarrollo

## Descripción
App de gestión de bolos (actuaciones de DJ), clientes y facturas. Desarrollada en Flutter para macOS con soporte futuro para móvil.

## Stack técnico
- **Framework:** Flutter 3.x / Dart 3.x
- **Estado:** Riverpod (StateNotifierProvider)
- **Navegación:** GoRouter con ShellRoute (5 pestañas)
- **BD local:** SQLite (sqflite + sqflite_common_ffi para desktop)
- **Cloud:** Supabase (sincronización de datos)
- **Google APIs:** googleapis + googleapis_auth (Calendar v3, Drive v3)
- **PDF:** pdf + printing
- **Gráficas:** fl_chart
- **Calendario:** table_calendar

## Estructura de navegación
| Pestaña    | Ruta         | Descripción                          |
|------------|--------------|--------------------------------------|
| Inicio     | /            | Dashboard con resumen y estadísticas |
| Calendario | /calendar    | Vista calendario con bolos           |
| Clientes   | /clients     | Lista y gestión de clientes          |
| Facturas   | /invoices    | Lista y gestión de facturas          |
| Mi Perfil  | /profile     | Cuenta Google, logo, datos emisor    |

- **Estadísticas** accesibles desde icono en AppBar del Dashboard (`/stats`)
- **Ajustes** accesibles desde icono en AppBar de Mi Perfil (`/settings`)

## Base de datos — Migraciones

### v1 (inicial)
- Tablas: `clients`, `gigs`, `invoices`, `invoice_items`, `app_settings`
- Campos base para todos los modelos

### v2
- `app_settings`: añadidos `emisor_provincia`, `emisor_codigo_postal`

### v3
- `clients`: añadidos `provincia`, `alias`

## Integración Google

### Autenticación
- **Paquete:** `googleapis_auth` (NO `google_sign_in`, que no soporta `client_secret` en desktop)
- **Flujo:** `clientViaUserConsent` → abre navegador → callback en localhost
- **Servicio:** `lib/services/google_auth_service.dart` (singleton)
- **Provider:** `googleAuthProvider` (StateNotifierProvider)

### Configuración OAuth
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

### Google Drive
- **Servicio:** `lib/services/google_drive_service.dart`
- Estructura de carpetas: `MisBolos/Facturas`, `MisBolos/Backups`
- Upload de PDFs de facturas
- Backup de base de datos

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
├── app.dart                           # MaterialApp + GoRouter (5 tabs)
├── models/
│   ├── app_settings.dart              # Settings del emisor
│   ├── client.dart                    # Cliente con alias, provincia
│   ├── gig.dart                       # Bolo/actuación
│   └── invoice.dart                   # Factura
├── database/
│   ├── database_helper.dart           # SQLite init + migraciones
│   └── migrations/
│       ├── v1_initial.dart
│       ├── v2_add_provincia_cp.dart
│       └── v3_add_client_provincia_alias.dart
├── services/
│   ├── google_auth_service.dart       # Auth centralizado (googleapis_auth)
│   ├── google_calendar_service.dart   # Sync con Google Calendar
│   ├── google_drive_service.dart      # Upload a Google Drive
│   └── notification_service.dart
├── screens/
│   ├── dashboard/                     # Inicio
│   ├── calendar/                      # Calendario + detalle de bolo
│   ├── clients/                       # Lista, detalle, formulario
│   ├── invoices/                      # Lista, detalle, formulario
│   ├── profile/                       # Mi Perfil (Google + datos emisor)
│   ├── settings/                      # Ajustes (IVA, notificaciones, etc.)
│   └── stats/                         # Estadísticas
├── providers/                         # Riverpod providers
├── repositories/                      # Acceso a BD
└── widgets/                           # Widgets compartidos
```

## Variables de entorno (.env)
```
SUPABASE_URL=https://utkuxjplwggfndnaqqir.supabase.co
SUPABASE_ANON_KEY=***
SUPABASE_SERVICE_ROLE_KEY=***
GOOGLE_CLIENT_ID=744196169382-knr1najrpc3muiim38k3epg6rdmdpuhj.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=***
```
