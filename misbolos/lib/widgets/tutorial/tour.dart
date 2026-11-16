import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Un paso de un tour: a qué elemento señala y qué cuenta.
@immutable
class PasoTour {
  /// La clave del widget real de la pantalla.
  final GlobalKey clave;

  final String texto;

  /// Recorte redondo para los botones; el rectangular es para tarjetas y
  /// campos.
  final bool redondo;

  const PasoTour({
    required this.clave,
    required this.texto,
    this.redondo = false,
  });
}

/// En escritorio el menú de acciones se abre con el clic derecho, así que los
/// textos que hablan de mantener pulsado tienen que decir otra cosa.
bool get esEscritorio =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Los pasos del tour de Inicio.
List<PasoTour> pasosDeInicio({
  required GlobalKey periodo,
  required GlobalKey ingresos,
  required GlobalKey impuestos,
  required GlobalKey anadir,
}) => [
  PasoTour(
    clave: periodo,
    texto:
        'Elige si quieres ver el mes, el trimestre o el año. Desliza a los '
        'lados para cambiar de periodo.',
  ),
  PasoTour(
    clave: ingresos,
    texto:
        'Lo que has cobrado, lo que te deben y lo que tienes previsto si '
        'cobras todo.',
  ),
  PasoTour(
    clave: impuestos,
    texto:
        'Una estimación de lo que conviene reservar para Hacienda: IVA e IRPF '
        'de tus facturas. Es orientativa: confírmala con tu gestoría.',
  ),
  PasoTour(
    clave: anadir,
    redondo: true,
    texto:
        'Desde aquí añades un bolo nuevo. Y en cualquier lista, tira hacia '
        'abajo para sincronizar tus datos.',
  ),
];

/// Los pasos del tour de Agenda.
///
/// [bolo] es opcional: si no hay ningún bolo en la lista del día, ese paso no
/// está.
List<PasoTour> pasosDeAgenda({
  required GlobalKey calendario,
  GlobalKey? bolo,
  required GlobalKey fechasLibres,
  GlobalKey? sincronizar,
}) => [
  PasoTour(
    clave: calendario,
    texto: esEscritorio
        // En los días del calendario no hay clic derecho, así que aquí se
        // sigue hablando de mantener pulsado, que también funciona con ratón.
        ? 'Tus bolos, por colores según su estado. Haz clic en un día para '
              'ver qué tienes, o mantenlo pulsado para crear un bolo ese día.'
        : 'Tus bolos, por colores según su estado. Toca un día para ver qué '
              'tienes, o mantenlo pulsado para crear un bolo ese día.',
  ),
  if (bolo != null)
    PasoTour(
      clave: bolo,
      texto: esEscritorio
          ? 'Haz clic derecho en un bolo para ver sus acciones: editar, '
                'duplicar, facturar o cancelar.'
          : 'Mantén pulsado un bolo para ver sus acciones: editar, duplicar, '
                'facturar o cancelar.',
    ),
  PasoTour(
    clave: fechasLibres,
    redondo: true,
    texto:
        'Genera un texto con tus días libres del mes para mandarlo por '
        'WhatsApp.',
  ),
  if (sincronizar != null)
    PasoTour(
      clave: sincronizar,
      redondo: true,
      texto: 'Sincroniza tus bolos con Google Calendar si lo tienes conectado.',
    ),
];

/// Los pasos del tour del formulario de bolo.
List<PasoTour> pasosDeNuevoBolo({
  required GlobalKey cliente,
  required GlobalKey cachet,
  required GlobalKey franja,
  required GlobalKey facturable,
  required GlobalKey guardar,
}) => [
  PasoTour(
    clave: cliente,
    texto:
        'Elige el cliente o crea uno nuevo. Con sus datos fiscales podrás '
        'facturarle.',
  ),
  PasoTour(clave: cachet, texto: 'Lo que cobras por el bolo, sin IVA.'),
  PasoTour(
    clave: franja,
    texto:
        'Indica si es de tarde, de noche o todo el día. Así Fechas libres sabe '
        'qué huecos te quedan.',
  ),
  PasoTour(
    clave: facturable,
    texto:
        'Actívalo si vas a emitir factura. Si no, el bolo cuenta como evento '
        'privado.',
  ),
  PasoTour(
    clave: guardar,
    redondo: true,
    texto: 'Guarda el bolo. Puedes editarlo cuando quieras.',
  ),
];

/// Los pasos del tour de Facturas.
///
/// [factura] es opcional: solo hay paso si se ve alguna pendiente de cobro.
List<PasoTour> pasosDeFacturas({
  required GlobalKey lista,
  required GlobalKey filtros,
  GlobalKey? factura,
}) => [
  PasoTour(
    clave: lista,
    texto:
        'Aquí aparecen tus facturas: borrador, pendiente de cobro o cobrada.',
  ),
  PasoTour(
    clave: filtros,
    texto: 'Filtra para ver, por ejemplo, solo lo que te deben.',
  ),
  if (factura != null)
    PasoTour(
      clave: factura,
      texto: esEscritorio
          ? 'Desliza una factura pendiente a la derecha para marcarla como '
                'cobrada. Si te equivocas, pulsa Deshacer. Haz clic derecho en '
                'ella para ver más acciones.'
          : 'Desliza una factura pendiente a la derecha para marcarla como '
                'cobrada. Si te equivocas, pulsa Deshacer. Mantenla pulsada '
                'para ver más acciones.',
    ),
];

/// Los pasos del tour de Gastos e Inversiones.
///
/// [gasto] es opcional: solo hay paso si hay alguno en la lista.
List<PasoTour> pasosDeGastos({required GlobalKey anadir, GlobalKey? gasto}) => [
  PasoTour(
    clave: anadir,
    redondo: true,
    texto:
        'Sube el PDF de un gasto o una compra. La app intenta leer la fecha, '
        'el total y el proveedor: revísalos siempre antes de guardar.',
  ),
  if (gasto != null)
    PasoTour(
      clave: gasto,
      texto:
          'El PDF se guarda en tu Drive, ordenado por trimestre y mes. Desliza '
          'un gasto a la izquierda para borrarlo; tienes unos segundos para '
          'deshacerlo y el PDF se queda en Drive.',
    ),
];

/// Los pasos del tour de Perfil.
List<PasoTour> pasosDePerfil({
  required GlobalKey datosFiscales,
  required GlobalKey google,
}) => [
  PasoTour(
    clave: datosFiscales,
    texto:
        'Rellena tu nombre, NIF y dirección. Son obligatorios para tus '
        'facturas.',
  ),
  PasoTour(
    clave: google,
    texto:
        'Conecta Google para guardar tus facturas en Drive y tus bolos en '
        'Calendar.',
  ),
];

/// Los pasos del tour de Ajustes.
List<PasoTour> pasosDeAjustes({required GlobalKey retencion}) => [
  PasoTour(
    clave: retencion,
    texto:
        'El porcentaje que se aplica por defecto en cada factura. Pulsa la i '
        'si tienes dudas.',
  ),
];
