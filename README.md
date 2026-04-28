# MisBolos

App de gestión de bolos (actuaciones DJ), clientes y facturación para autónomos.
Preparada para **multi-usuario**: cada DJ tiene sus propios datos aislados.

## Documentación

- [PROYECTO.md](PROYECTO.md): descripción completa del proyecto, sus módulos y
  su lógica de negocio.
- [PROCESO.md](PROCESO.md): registro técnico de desarrollo, migraciones y
  decisiones internas.

## Funcionalidades

- **Dashboard** con resumen de ingresos oficiales y "en B"
- **Calendario** con vista mensual de bolos
- **Gestión de clientes** con historial de bolos y gestión de duplicados
- **Facturación** con generación de PDF profesional (6 temas de color), soporte IRPF
- **Estadísticas** con gráficos mensuales y exportación CSV
- **Resumen financiero** con declaración trimestral de IVA
- **Importación** de bolos desde CSV o Excel
- **Sincronización opcional** con Supabase (solo datos oficiales)
- **Notificaciones** de cobro pendiente

## Privacidad y seguridad

- **Multi-usuario**: cada DJ solo ve y modifica sus propios datos (Row Level Security con `auth.uid() = user_id`)
- El `user_id` se asigna automáticamente por trigger al insertar — no se puede falsificar desde el cliente
- Los números de factura son únicos **por usuario**, no globales
- Los bolos marcados como **"No Facturable" (en B)** nunca salen del dispositivo:
- No se sincronizan con Supabase
  - No se incluyen en backups

## Requisitos

- Flutter 3.x
- Dart 3.x

## Configuración

### 1. Dependencias

```bash
cd misbolos
flutter pub get
```

### 2. Supabase (opcional)

1. Crea un proyecto en [supabase.com](https://supabase.com)
2. Ejecuta `supabase/schema.sql` en el SQL Editor de tu proyecto
3. Copia la URL y la clave anónima (anon key)
4. Introdúcelos en Ajustes > Supabase dentro de la app

### 3. Autenticación Google (sincronización)

**macOS:**
1. Ve a [Google Cloud Console](https://console.cloud.google.com)
2. Crea un proyecto y habilita Calendar API y Drive API
3. Crea credenciales OAuth 2.0 de tipo **Desktop**
4. El flujo usa `googleapis_auth` con `clientViaUserConsent` (abre el navegador)

**iOS / Android:**
1. Crea credenciales OAuth 2.0 de tipo **Android** / **iOS** en Google Cloud Console
2. Configura `google_sign_in` según la [documentación oficial](https://pub.dev/packages/google_sign_in)
3. El ID token obtenido se usa para autenticar en Supabase (`signInWithIdToken`)

### 4. Permisos Android

En `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
```

### 5. Permisos iOS

En `ios/Runner/Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Para seleccionar el logo de tu empresa</string>
```

### 6. Notificaciones

Las notificaciones locales se configuran automáticamente al activarlas en Ajustes.
En Android 13+ se solicitará permiso de notificaciones al usuario.

## Estructura del proyecto

```
lib/
├── main.dart                 # Punto de entrada
├── app.dart                  # GoRouter + MisBolosApp
├── core/
│   ├── constants/            # Colores, tipografía, strings
│   ├── theme/                # ThemeData light/dark
│   └── utils/                # Formatters, generador de nº factura
├── models/                   # Client, Gig, Invoice, AppSettings
├── database/
│   ├── database_helper.dart  # Singleton SQLite
│   └── migrations/           # SQL de creación de tablas
├── repositories/             # CRUD para cada modelo
├── providers/                # Riverpod state management
├── services/                 # PDF, Supabase, Google Drive, Notificaciones
├── screens/                  # Todas las pantallas
└── widgets/                  # Widgets reutilizables
```

## Ejecución

```bash
flutter run
```

## Licencia

Uso privado.
