# MisBolos — Descripción completa del proyecto

## Qué es

MisBolos es una app para DJs y profesionales autónomos que necesitan gestionar
su actividad de forma práctica desde una sola herramienta. El proyecto cubre
la parte operativa del día a día: bolos, clientes, facturas, gastos,
inversiones, resúmenes financieros, sincronización y documentación en PDF.

La idea principal es juntar en una misma aplicación tres planos que suelen
estar separados:

- La agenda real de actuaciones.
- La relación comercial con clientes.
- El control económico y fiscal del negocio.

## Qué problema resuelve

Un DJ autónomo suele trabajar con información repartida entre calendario,
mensajes, hojas de cálculo, facturas sueltas y notas personales. MisBolos
centraliza ese flujo para que cada bolo pueda convertirse en un registro útil
para la operación, la facturación y el seguimiento financiero.

La app permite distinguir entre actividad oficial y actividad no facturable
"en B", sin mezclar ambas cosas en la sincronización cloud ni en los resúmenes
que no correspondan.

## Objetivos del proyecto

- Tener una base local robusta para que la app funcione sin depender de
  internet.
- Mantener sincronización opcional en la nube para los datos oficiales.
- Facilitar la emisión de facturas, el seguimiento de cobros y el control de
  IVA/IRPF.
- Dar visibilidad rápida del estado del negocio desde un dashboard claro.
- Permitir que el mismo código base sirva para escritorio y móvil.

## Funcionalidades principales

### 1. Dashboard

Pantalla inicial con visión rápida del negocio:

- Resumen de cobrado, pendiente y previsto.
- Separación entre ingresos oficiales, ingresos en B y totales combinados.
- Alertas de facturas pendientes.
- Accesos a estadísticas y resúmenes financieros.

### 2. Agenda de bolos

La agenda es el centro operativo del proyecto:

- Vista calendario mensual.
- Alta, edición y cancelación de bolos.
- Estado de cada bolo: pendiente, cobrado, factura generada, factura enviada,
  pagado, etc.
- Distinción entre bolo facturable y bolo en B.
- Integración opcional con Google Calendar.

### 3. Clientes

Cada cliente tiene su propio historial y contexto:

- Ficha de cliente con datos de contacto.
- Alias y deduplicación.
- Historial de bolos y relación con facturas.
- Reutilización del cliente en formularios y resúmenes.

### 4. Facturas

El módulo de facturación conecta la parte comercial con la financiera:

- Creación de facturas a partir de bolos.
- Estados de factura: borrador, enviada, pagada.
- Generación de PDF.
- Soporte para IVA e IRPF.
- Reenumeración y ordenación.
- Selección múltiple y envío conjunto.
- Sincronización con el estado del bolo asociado.

### 5. Gastos

El módulo de gastos registra costes deducibles y no deducibles:

- Alta y edición de gastos.
- Filtro por categoría, año y mes.
- Ordenación por fecha e importe.
- Cálculo de total de gastos e IVA soportado.
- Persistencia local con posibilidad de sincronización.

### 6. Inversiones

El proyecto también cubre inmovilizado e inversiones:

- Registro de compras amortizables.
- Clasificación por categoría.
- Cálculo de valor contable y amortización.
- Separación entre base amortizable e IVA soportado.
- Resumen de inversión total y amortización trimestral.

### 7. Perfil y ajustes

La configuración personal del emisor forma parte del núcleo del producto:

- Datos fiscales del emisor.
- Logo y apariencia de PDF.
- IVA por defecto.
- Integración con Google.
- Configuración de Supabase.
- Notificaciones y comportamiento de sincronización.

## Enfoque de datos

MisBolos sigue una estrategia "local first":

- La base principal es SQLite.
- La app puede funcionar offline.
- La sincronización cloud es opcional.
- Los datos no facturables no se suben a Supabase.

Esto permite trabajar con seguridad incluso sin conexión, manteniendo la nube
como apoyo y no como dependencia total.

## Distinción entre oficial y B

Una parte importante del proyecto es la separación entre actividad oficial y
actividad en B.

- Los bolos facturables pueden generar factura, estados de cobro y resúmenes
  oficiales.
- Los bolos en B quedan en el dispositivo y forman parte de sus propios
  resúmenes.
- El dashboard y las vistas financieras pueden mostrar oficial, B y total
  combinado.

Ese comportamiento no es accesorio: forma parte del diseño funcional del
proyecto.

## Arquitectura general

El proyecto está estructurado en capas sencillas y bastante claras:

- `models/`: entidades del dominio.
- `database/`: inicialización y migraciones SQLite.
- `repositories/`: acceso a datos.
- `providers/`: estado y lógica reactiva con Riverpod.
- `services/`: PDF, Supabase, Google, notificaciones, importación.
- `screens/`: pantallas de la app.
- `widgets/`: piezas reutilizables de UI.

## Flujo principal de negocio

El flujo más importante de la app suele ser este:

1. Se crea o registra un bolo.
2. El bolo se asocia a un cliente.
3. Si es facturable, puede generar una factura.
4. La factura cambia de estado a medida que se envía o se cobra.
5. El estado de la factura repercute en el estado del bolo.
6. El dashboard y los resúmenes financieros reflejan ese estado actualizado.

## Tecnologías principales

- Flutter / Dart
- Riverpod
- GoRouter
- SQLite
- Supabase
- Google Calendar / Google Auth
- `pdf` y `printing`

## Estado actual del proyecto

El proyecto ya no es un prototipo simple: tiene varios módulos conectados,
persistencia local, sincronización, generación documental y lógica financiera
real. A la vez, sigue evolucionando mucho en la capa de UX y en los detalles
de consistencia entre módulos.

## Documentación relacionada

- [README.md](README.md): entrada rápida, instalación y ejecución.
- [PROCESO.md](PROCESO.md): registro técnico, decisiones, migraciones y notas
  de desarrollo.
