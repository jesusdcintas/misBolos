import 'package:flutter/foundation.dart';

/// Los nombres de las carpetas que la app crea en Drive.
///
/// Todo sale de aquí: ni la creación, ni la subida, ni el movimiento de un
/// adjunto al cambiar de fecha llevan el nombre escrito a mano.
const String carpetaFacturas = 'FACTURAS';
const String carpetaGastosEInversiones = 'GASTOS E INVERSIONES';

/// Carpetas de versiones anteriores que ya no se crean ni se usan.
///
/// No se borran de Drive: lo que el usuario tenga dentro se queda donde está.
const List<String> carpetasRetiradas = <String>['GASTOS', 'INVERSIONES'];

String getYearFolderName(DateTime date) => 'Contabilidad ${date.year}';

String getQuarterName(DateTime date) {
  if (date.month <= 3) return '1 TRIMESTRE';
  if (date.month <= 6) return '2 TRIMESTRE';
  if (date.month <= 9) return '3 TRIMESTRE';
  return '4 TRIMESTRE';
}

String getMonthName(DateTime date) {
  const months = [
    'ENERO',
    'FEBRERO',
    'MARZO',
    'ABRIL',
    'MAYO',
    'JUNIO',
    'JULIO',
    'AGOSTO',
    'SEPTIEMBRE',
    'OCTUBRE',
    'NOVIEMBRE',
    'DICIEMBRE',
  ];
  return months[date.month - 1];
}

/// Una carpeta de un año, con lo que cuelga de ella.
@immutable
class NodoCarpeta {
  final String nombre;
  final List<NodoCarpeta> hijos;

  const NodoCarpeta(this.nombre, [this.hijos = const []]);
}

/// El árbol que hay que tener en Drive para [ano].
///
/// Año → trimestre → mes → las dos carpetas de documentos. Son 41 carpetas:
/// 1 + 4 + 12 + 24.
NodoCarpeta arbolDeAno(int ano) {
  return NodoCarpeta(getYearFolderName(DateTime(ano)), [
    for (var trimestre = 0; trimestre < 4; trimestre++)
      NodoCarpeta(getQuarterName(DateTime(ano, trimestre * 3 + 1)), [
        for (var mes = 1; mes <= 3; mes++)
          NodoCarpeta(getMonthName(DateTime(ano, trimestre * 3 + mes)), const [
            NodoCarpeta(carpetaFacturas),
            NodoCarpeta(carpetaGastosEInversiones),
          ]),
      ]),
  ]);
}

/// Cuántas carpetas hay en [nodo], contándolo a él.
int cuentaCarpetas(NodoCarpeta nodo) =>
    1 + nodo.hijos.fold(0, (suma, hijo) => suma + cuentaCarpetas(hijo));

/// Una carpeta de Drive vista desde fuera: lo justo para poder decidir.
@immutable
class CarpetaDrive {
  final String id;
  final String nombre;

  const CarpetaDrive({required this.id, required this.nombre});
}

/// Qué hacer con la carpeta de gastos e inversiones de un mes.
enum AccionCarpetaGastos {
  /// No hay ninguna: se crea.
  crear,

  /// Ya está con el nombre bueno.
  usar,

  /// Está la antigua («Gastos e Inversiones»): se renombra en su sitio, sin
  /// crear otra ni mover ficheros.
  renombrar,

  /// Están las dos. No se fusionan: se usa la de mayúsculas y se avisa.
  duplicadas,
}

@immutable
class DecisionCarpetaGastos {
  final AccionCarpetaGastos accion;

  /// La carpeta que hay que usar o renombrar. Null si hay que crearla.
  final String? id;

  const DecisionCarpetaGastos(this.accion, [this.id]);
}

/// Decide qué hacer con las carpetas [hijas] de un mes.
///
/// Compara los nombres en Dart, sin depender de si Drive distingue mayúsculas
/// al buscar, que es algo que cambia según la consulta.
DecisionCarpetaGastos decidirCarpetaGastos(List<CarpetaDrive> hijas) {
  CarpetaDrive? exacta;
  CarpetaDrive? variante;

  for (final hija in hijas) {
    if (hija.nombre == carpetaGastosEInversiones) {
      exacta ??= hija;
      continue;
    }
    if (hija.nombre.trim().toUpperCase() == carpetaGastosEInversiones) {
      variante ??= hija;
    }
  }

  if (exacta != null && variante != null) {
    return DecisionCarpetaGastos(AccionCarpetaGastos.duplicadas, exacta.id);
  }
  if (exacta != null) {
    return DecisionCarpetaGastos(AccionCarpetaGastos.usar, exacta.id);
  }
  if (variante != null) {
    return DecisionCarpetaGastos(AccionCarpetaGastos.renombrar, variante.id);
  }
  return const DecisionCarpetaGastos(AccionCarpetaGastos.crear);
}
