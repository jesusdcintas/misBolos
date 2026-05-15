# Plan de integración Google Drive - MisBolos

## Objetivo
Google Drive será un backup documental y archivo ordenado de MisBolos, no la base de datos principal. La fuente de verdad seguirá siendo SQLite/Supabase. Drive guardará PDFs de facturas, adjuntos de gastos, adjuntos de inversiones y backups JSON organizados por año, trimestre y mes.

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

## Fase 7 - Backup JSON
Checklist:
- [x] Crear backup JSON completo.
- [x] Incluir clientes.
- [x] Incluir bolos oficiales.
- [x] Incluir facturas.
- [x] Incluir gastos.
- [x] Incluir inversiones.
- [x] Incluir configuración fiscal básica.
- [x] Incluir IDs de Drive asociados.
- [x] Incluir versión de esquema.
- [x] Guardar backup en BACKUPS APP.
- [x] Botón "Crear backup ahora".

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

## Fase 9 - Restauración futura
Checklist:
- [ ] Preparar estructura para restaurar backup.
- [ ] No activar restauración destructiva todavía.
- [ ] Mostrar backups disponibles.
- [ ] Crear copia local antes de restaurar.
- [ ] Resolver conflictos por updated_at.
- [ ] Dejar esta fase marcada como futura si es demasiado compleja.

## Fase 10 - Pruebas
Checklist:
- [ ] Probar con carpeta "MisBolos Test".
- [ ] Confirmar que no toca Contabilidad 2025.
- [ ] Confirmar que no toca Contabilidad 2026.
- [ ] Crear estructura en Drive.
- [ ] Subir factura de prueba.
- [ ] Subir gasto de prueba.
- [ ] Subir inversión de prueba.
- [ ] Crear backup JSON.
- [ ] Probar sin internet.
- [ ] Probar login cancelado.
- [ ] Probar reconexión.
- [ ] Probar que no duplica carpetas.
- [x] Ejecutar `flutter analyze`.
- [x] Ejecutar `flutter test`.

## Estado actual
- Completadas fases 1 a 4 en código.
- Preparada migración local para campos Drive y tabla `drive_sync_queue`.
- Preparados campos Drive en modelos de facturas, gastos e inversiones.
- Añadida tarjeta Google Drive en Mi Perfil con conexión, búsqueda, selección por `folderId`, apertura de carpeta y creación idempotente de estructura anual.
- Implementada sincronización manual de documentos existentes: facturas no borrador, adjuntos de gastos y adjuntos de inversiones.
- Las subidas fallidas quedan registradas en `drive_sync_queue`.
- Implementado backup JSON manual en Drive (`BACKUPS APP`) con datos de clientes, bolos oficiales, facturas, gastos, inversiones y configuración fiscal básica.
- Implementada subida automática de facturas a Drive al guardar (si Drive está conectado y hay carpeta raíz seleccionada).
- Añadido botón manual "Subir a Drive" en detalle de factura.
- Implementado reintento manual de cola `drive_sync_queue` con límite de intentos y resumen de errores en UI.
- No se ha ejecutado ninguna acción real sobre Drive desde código durante esta sesión; solo queda disponible para que el usuario la lance desde la carpeta seleccionada.
- Pendiente restauración futura y pruebas E2E reales en Drive.
- Pendiente crítico detectado en producción: en "Subir documentos a Drive" algunas inversiones/gastos existentes no se suben si el adjunto local se perdió y el registro ya existía; requiere cierre definitivo del flujo de recuperación/re-subida masiva para adjuntos no locales.
