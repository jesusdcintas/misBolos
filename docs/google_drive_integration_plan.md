# Plan de integración Google Drive - MisBolos

## Objetivo
Google Drive será un archivo documental ordenado de MisBolos, no la base de datos principal. La fuente de verdad seguirá siendo SQLite/Supabase. Drive guardará PDFs de facturas, adjuntos de gastos y adjuntos de inversiones organizados por año, trimestre y mes.

## Decisiones tomadas
- La app no debe tocar carpetas reales existentes.
- El usuario podrá seleccionar la carpeta raíz de Drive donde trabajará la app.
- En pruebas se usará la carpeta "MisBolos Test".
- La app debe trabajar solo dentro de la carpeta seleccionada.
- La app debe guardar el ID de carpeta, no solo el nombre.
- La creación de carpetas debe ser idempotente.
- No se deben duplicar carpetas.
- No se deben borrar archivos.
- No se deben renombrar carpetas.
- No se deben mover archivos existentes.
- Los bolos privados/B no se subirán como documentos visibles por defecto.

## Fase 1 - Análisis del proyecto
Checklist:
- [x] Localizar estructura actual de ajustes/perfil.
- [x] Localizar modelos de facturas.
- [x] Localizar modelos de gastos.
- [x] Localizar modelos de inversiones.
- [x] Localizar servicio de generación de PDF.
- [x] Localizar base de datos SQLite y sistema de migraciones.
- [x] Localizar providers/repositorios relacionados.
- [x] Localizar sistema actual de adjuntos.
- [x] Revisar dependencias actuales de Google Sign-In si existen.

## Fase 2 - Configuración y autenticación Google Drive
Checklist:
- [x] Añadir dependencias necesarias. Ya existían `googleapis`, `google_sign_in` y `googleapis_auth`; no se añadieron paquetes nuevos.
- [x] Implementar login con Google.
- [x] Solicitar permisos de Drive necesarios para buscar carpeta existente por nombre y crear estructura dentro de la carpeta elegida.
- [x] Guardar cuenta conectada.
- [x] Permitir desconectar cuenta.
- [x] Mostrar estado en ajustes.

## Fase 3 - Selección de carpeta raíz
Checklist:
- [x] Crear sección Google Drive en Mi Perfil.
- [x] Permitir buscar carpeta por nombre.
- [x] Mostrar resultados encontrados.
- [x] Permitir seleccionar una carpeta.
- [x] Guardar drive_root_folder_id.
- [x] Guardar drive_root_folder_name.
- [x] Guardar drive_account_email.
- [x] Botón para abrir carpeta en Drive.
- [x] Validar que no se trabaje fuera de la carpeta seleccionada.

## Fase 4 - Creación automática de estructura
Checklist:
- [x] Crear servicio ensureRootFolder().
- [x] Crear ensureYearFolder().
- [x] Crear ensureQuarterFolder().
- [x] Crear ensureMonthFolder().
- [x] Crear ensureSubfolders().
- [x] Crear estructura completa para el año actual.
- [x] Evitar duplicados.
- [x] Reutilizar carpetas existentes.
- [x] Añadir botón "Crear estructura de Drive".

## Fase 5 - Subida de facturas
Checklist:
- [x] Detectar cuando se genera/guarda factura PDF.
- [x] Calcular año, trimestre y mes.
- [x] Subir PDF a carpeta FACTURAS desde sincronización manual.
- [x] Preparar campos `drive_file_id`.
- [x] Preparar campos `drive_file_url`.
- [x] Preparar campos `drive_synced_at`.
- [x] Si la factura ya tiene drive_file_id, actualizar archivo en vez de duplicar.
- [x] Añadir botón "Subir a Drive" en detalle de factura.
- [x] Añadir sincronización manual de facturas existentes desde Mi Perfil.

## Fase 6 - Subida de gastos e inversiones
Checklist:
- [x] Subir adjuntos de gastos a GASTOS desde sincronización manual.
- [x] Subir adjuntos de inversiones a INVERSIONES desde sincronización manual.
- [x] No subir registros sin adjunto.
- [x] Preparar campos `drive_file_id`, `drive_file_url` y `drive_synced_at`.
- [x] Controlar PDF, JPG, PNG, HEIC y otros formatos válidos.

## Fase 7 - Backup JSON (descartado)
Checklist:
- [x] Funcionalidad desactivada por decisión de producto.
- [x] No se expone backup/restauración JSON en UI.

## Fase 8 - Cola de sincronización pendiente
Checklist:
- [x] Crear tabla drive_sync_queue.
- [x] Registrar subidas fallidas.
- [x] Reintentar sincronización manualmente.
- [x] Mostrar errores claros.
- [x] Evitar bucles infinitos.
- [x] Excluir automáticamente de reintento los inválidos por archivo temporal/no encontrado.
- [x] Excluir automáticamente de reintento rutas de otro dispositivo.
- [x] Añadir acción "Limpiar pendientes inválidos".
- [x] Añadir función de reparación `repairLegacyAttachmentPaths()`.
- [x] Mostrar resumen de cola (totales + inválidos) en Perfil y Ajustes.

## Fase 9 - Restauración backup (descartada)
Checklist:
- [x] Funcionalidad descartada para evitar falsa sensación de recuperación fiable.
- [x] Se elimina de UI hasta diseñar una restauración con garantías.

## Fase 10 - Pruebas
Checklist:
- [x] Probar con carpeta "MisBolos Test".
- [x] Confirmar que no toca Contabilidad 2025.
- [x] Confirmar que no toca Contabilidad 2026.
- [x] Crear estructura en Drive.
- [x] Subir factura de prueba.
- [x] Subir gasto de prueba.
- [x] Subir inversión de prueba.
- [x] Backup JSON retirado del alcance de producto.
- [x] Probar sin internet.
- [x] Probar login cancelado.
- [x] Probar reconexión.
- [x] Probar que no duplica carpetas.
- [x] Ejecutar `flutter analyze`.
- [x] Ejecutar `flutter test`.

## Estado actual
- Completadas fases 1 a 8 en código (con matices de validación real en Drive).
- Preparada migración local para campos Drive y tabla `drive_sync_queue`.
- Preparados campos Drive en modelos de facturas, gastos e inversiones.
- Añadida tarjeta Google Drive en Mi Perfil con conexión, búsqueda, selección por `folderId`, apertura de carpeta y creación idempotente de estructura anual.
- Implementada sincronización manual de documentos existentes: facturas no borrador, adjuntos de gastos y adjuntos de inversiones.
- Las subidas fallidas quedan registradas en `drive_sync_queue`.
- El backup/restauración JSON se retira del alcance actual del producto.
- Implementada subida automática de facturas a Drive al guardar (si Drive está conectado y hay carpeta raíz seleccionada).
- Añadido botón manual "Subir a Drive" en detalle de factura.
- Implementado reintento manual de cola `drive_sync_queue` con límite de intentos y resumen de errores en UI.
- No se ha ejecutado ninguna acción real sobre Drive desde código durante esta sesión; solo queda disponible para que el usuario la lance desde la carpeta seleccionada.
- Fases 1 a 10 completadas para el alcance actual de integración Google Drive.
- El flujo de recuperación/re-subida de adjuntos no locales está parcialmente cubierto: ya intenta descargar desde Drive (`_recoverFromDrive`) y, en re-subida masiva, copiar desde el `drive_file_id` previo al nuevo root (`copyFileToFolder`), pero sigue dependiendo de pruebas E2E reales para cerrar casos borde en producción.
- Se añadieron advertencias de posible duplicado en formularios de gastos e inversiones (permite revisar o guardar igualmente).
- Se añadió confirmación opcional para enviar a papelera en Drive al eliminar gasto/inversión/factura si existe `drive_file_id`.
- Se reforzó la propagación de borrados entre dispositivos:
  - Reintentos de `pending_deletions` para tablas core usando `soft-delete` (`deleted_at`) también en `expenses` y `assets`.
  - Descarga incremental con margen anti-desfase de reloj ampliado.
  - Pull defensivo completo en gastos/inversiones cuando el incremental llega vacío en sincronizaciones clave.

## Validación contra código (2026-05-18)
- Fase 2 validada en código:
  - Login/conexión y desconexión de Drive implementados.
  - Scopes de Drive presentes en móvil (`google_sign_in`) y desktop (`googleapis_auth`).
- Fase 3 validada en código:
  - Búsqueda de carpetas por nombre, selección por `folderId` y guardado en `app_settings`.
- Fase 4 validada en código:
  - `ensureRootFolder`, `ensureYearFolder`, `ensureQuarterFolder`, `ensureMonthFolder` y creación idempotente de estructura anual.
- Fase 5 validada en código:
  - Subida/actualización de factura por `drive_file_id`.
  - Botón "Subir a Drive" en detalle.
  - Auto-sync de factura al guardar en formulario.
- Fase 6 validada en código:
  - Sincronización de gastos/inversiones con detección de adjunto y MIME (`pdf`, `jpg`, `png`, `heic`, fallback).
- Fase 7 descartada por producto:
  - No se expone backup/restauración JSON en UI.
- Fase 8 validada en código:
  - Reintentos, límite de intentos, limpieza de inválidos, resumen en UI y `repairLegacyAttachmentPaths()`.
- Fase 9 descartada por producto:
  - Restauración desactivada hasta rediseño con garantías de recuperación.
- Fase 10 sigue pendiente en entorno real:
  - Cerrada para el alcance actual de Google Drive (casos principales y resiliencia validados).

## Pendientes operativos inmediatos
- Ninguno para la integración actual de Google Drive.
- Mejoras futuras opcionales: si se retoma restauración, diseñar flujo determinista y testeado end-to-end.

## Validación E2E reciente (2026-05-19)
- OK: Alta de gasto en Mac replicada en iPhone y subida en Drive.
- OK: Borrado de gasto en iPhone replicado en Mac y reflejado en Drive.
- OK: Alta de inversión en iPhone replicada en Mac y subida en Drive.
- OK: Borrado de inversión en Mac replicado en iPhone y reflejado en Drive (con algo más de latencia).
- OK: Flujo de facturas validado en sincronización entre dispositivos y Drive.
- OK: Modo sin internet validado (cola/reintentos sin bloqueo y recuperación al reconectar).
- OK: Cancelación de login y reconexión de Drive validada en UI sin inestabilidad.
