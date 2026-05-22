# Plan de implementación - Login principal con Supabase Auth (MisBolos)

> Nota: este plan está consolidado en [`docs/plan_maestro_implementacion.md`](./plan_maestro_implementacion.md).

## Objetivo
Forzar autenticación al abrir la app usando Supabase Auth como fuente única de identidad, con soporte de:
- Email + contraseña (login/registro/recover)
- Sesión persistente
- Login con Google (fase 2)

---

## Estrategia de entrega
Se implementa en 2 fases para minimizar bugs:

1. **Fase 1 (prioritaria):**
   - Login principal con email/contraseña
   - Registro
   - Recuperar contraseña
   - Persistencia de sesión
   - Rutas públicas/privadas con GoRouter
   - Logout seguro
   - Aislamiento de datos por `user_id`

2. **Fase 2:**
   - Google Sign-In (iOS/Android con token a Supabase)
   - Compatibilidad macOS con flujo OAuth actual

---

## Alcance funcional

### Flujo de arranque
- En `main/app bootstrap` comprobar `Supabase.instance.client.auth.currentSession`.
- Si hay sesión válida: entrar a rutas privadas.
- Si no hay sesión: ir a `/login`.
- Mantener acceso offline si sesión persistida existe.

### Pantallas Auth
- `/login`
  - email + contraseña
  - botón ir a registro
  - botón ir a recuperar contraseña
  - botón Google (fase 2, puede quedar deshabilitado en fase 1)
- `/register`
  - alta con email + contraseña
- `/forgot-password`
  - solicitar reset password

### GoRouter (control de acceso)
- **Públicas:** `/login`, `/register`, `/forgot-password`
- **Privadas:** resto de la app
- Redirect centralizado según estado de sesión (reactivo a `authStateChanges`).

### Logout
- Botón “Cerrar sesión” en Perfil.
- Al cerrar sesión:
  - `supabase.auth.signOut()`
  - invalidar providers de estado/sync
  - impedir fuga de datos del usuario previo
  - política de datos local: **filtrar por `user_id`** (no borrar agresivo por defecto)

---

## Modelo de datos y seguridad

### SQLite local
- Todas las consultas de entidades de negocio deben filtrar por `user_id`.
- Inserts/upserts deben guardar `user_id = auth.currentUser.id`.
- Revisar repositorios: clients, gigs, invoices, expenses, assets, settings vinculados a usuario.

### Supabase
- Verificar `user_id uuid` en tablas core.
- Verificar/crear policies RLS:
  - `auth.uid() = user_id` para select/insert/update/delete.
- Mantener compatibilidad con soft-delete existente (`deleted_at`).

---

## Manejo de errores (UX)
Mostrar mensajes claros para:
- credenciales incorrectas
- email no confirmado
- error de red
- recuperación de contraseña fallida
- Google cancelado (fase 2)

---

## Checklist técnica

### Fase 1 - Email/Password + sesión persistente
- [x] Crear `AuthController` (estado de sesión + acciones auth).
- [x] Crear pantalla `LoginScreen` (`/login`).
- [x] Crear pantalla `RegisterScreen` (`/register`).
- [x] Crear pantalla `ForgotPasswordScreen` (`/forgot-password`).
- [x] Integrar flujo de login email/password con Supabase.
- [x] Integrar flujo de registro con Supabase.
- [x] Integrar recuperación de contraseña.
- [x] Integrar sesión persistente en arranque (`currentSession`).
- [x] Implementar guardas de rutas públicas/privadas en GoRouter.
- [x] Añadir botón “Cerrar sesión” en Perfil.
- [x] Implementar limpieza de estado al logout (providers/sync/UI).
- [x] Revisar repositorios SQLite para filtrar por `user_id`.
- [x] Revisar escritura de `user_id` en altas/updates.
- [x] Revisar RLS de tablas core en Supabase.
- [x] Probar modo offline con sesión guardada.
- [x] Probar bloqueo de acceso sin sesión y sin red.

### Fase 2 - Google Sign-In
- [x] Implementar login Google iOS/Android (`google_sign_in` + tokens a Supabase).
- [x] Integrar flujo compatible en macOS (OAuth actual).
- [x] Mapear errores Google (cancelado/red/token inválido).
- [x] Validar coexistencia con login email/password.

---

## Checklist QA (manual)

### Autenticación
- [x] Login correcto con email/contraseña.
- [x] Error visible con contraseña incorrecta.
- [x] Registro correcto de nuevo usuario.
- [x] Recuperación de contraseña envía email/reset.
- [x] Redirección automática a app privada tras login.
- [x] Redirección a login al hacer logout.

### Sesión y routing
- [x] Con sesión activa, app abre en privado sin pedir login.
- [x] Sin sesión, app abre en `/login`.
- [x] Ruta privada no accesible sin sesión.

### Datos por usuario
- [x] Usuario A no ve datos de usuario B en ninguna pantalla.
- [x] Sync solo sube/descarga datos del `user_id` activo.
- [x] Logout/login con otro usuario no mezcla datos.

### Offline
- [x] Con sesión persistida y sin internet, se puede entrar.
- [x] Sin sesión y sin internet, login bloqueado con mensaje claro.

### Google (fase 2)
- [x] Login Google correcto.
- [x] Cancelación Google muestra mensaje controlado.
- [x] Usuario Google entra en rutas privadas como email/password.

---

## Riesgos y decisiones
- Riesgo principal: fuga de datos entre usuarios por consultas SQLite sin filtro.
- Decisión actual implementada: limpieza de datos locales de usuario al hacer logout (`clearUserScopedData`) para evitar cualquier fuga entre sesiones en el mismo dispositivo.
- Si se detectan datos legacy sin `user_id`, preparar migración de saneo.

---

## Estado validado en código (2026-05-22)
- AuthController, pantallas Auth y rutas públicas/privadas: implementado.
- Login/registro/recuperación/reset: implementado.
- Sesión persistente + guardas GoRouter: implementado.
- Login Google (iOS/Android/macOS) y manejo de errores: implementado.
- Logout en Perfil y limpieza de estado/sesión: implementado.
- Filtrado y sync por `user_id` con RLS en tablas core: implementado.

---

## Entregables
- Pantallas Auth (`/login`, `/register`, `/forgot-password`).
- `AuthController` + providers de sesión.
- GoRouter con guardas públicas/privadas.
- Login email/password + registro + recovery.
- Logout en Perfil.
- Ajustes `user_id` en repositorios/sync.
- Google login (fase 2).
