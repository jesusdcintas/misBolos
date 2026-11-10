import 'package:flutter/foundation.dart';

import '../../models/gig.dart';

/// Clave de un día: año, mes y día en UTC, sin horas.
///
/// Todas las fechas de este fichero (claves del mapa de ocupación, retoques
/// manuales y resultado) se normalizan así, para que dos bolos del mismo día a
/// horas distintas caigan en la misma clave y para que el cambio de hora no
/// desplace ningún día.
DateTime diaClave(DateTime fecha) =>
    DateTime.utc(fecha.year, fecha.month, fecha.day);

/// Franjas de un día ocupadas por bolos.
///
/// Hoy un bolo ocupa el día entero y siempre marca las dos franjas. Está
/// separado así para que, cuando los bolos tengan franja, solo haya que
/// cambiar [ocupacionDeBolo] y el filtro de la consulta.
@immutable
class OcupacionDia {
  final bool tarde;
  final bool noche;

  const OcupacionDia({this.tarde = false, this.noche = false});

  /// Ningún bolo.
  static const OcupacionDia libre = OcupacionDia();

  /// El día entero.
  static const OcupacionDia completa = OcupacionDia(tarde: true, noche: true);

  bool get estaLibre => !tarde && !noche;

  /// Une dos ocupaciones: una franja ocupada en cualquiera queda ocupada.
  OcupacionDia mas(OcupacionDia otra) =>
      OcupacionDia(tarde: tarde || otra.tarde, noche: noche || otra.noche);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OcupacionDia && tarde == other.tarde && noche == other.noche;

  @override
  int get hashCode => Object.hash(tarde, noche);

  @override
  String toString() => 'OcupacionDia(tarde: $tarde, noche: $noche)';
}

/// Qué ocupa un bolo. De momento, el día entero.
OcupacionDia ocupacionDeBolo(Gig gig) => OcupacionDia.completa;

/// Ocupación de cada día a partir de los bolos.
///
/// Los bolos cancelados no ocupan. Varios bolos el mismo día se unen en una
/// sola ocupación.
Map<DateTime, OcupacionDia> ocupacionPorDia(List<Gig> gigs) {
  final ocupacion = <DateTime, OcupacionDia>{};
  for (final gig in gigs) {
    if (gig.status == GigStatus.cancelado) continue;
    final clave = diaClave(gig.fecha);
    ocupacion[clave] = (ocupacion[clave] ?? OcupacionDia.libre).mas(
      ocupacionDeBolo(gig),
    );
  }
  return ocupacion;
}

/// Días libres del mes [month] de [year], en orden.
///
/// Un día entra si está marcado y no tiene ningún bolo. Está marcado si su día
/// de la semana está en [diasSemana] (1 lunes … 7 domingo) o si se añadió a
/// mano en [anadidos]. [quitados] manda sobre los dos: un día que esté en
/// [quitados] nunca entra. Los días anteriores a [hoy] no salen nunca.
List<DateTime> diasLibres({
  required int year,
  required int month,
  required Set<int> diasSemana,
  Set<DateTime> anadidos = const {},
  Set<DateTime> quitados = const {},
  Map<DateTime, OcupacionDia> ocupacion = const {},
  DateTime? hoy,
}) {
  final desde = diaClave(hoy ?? DateTime.now());
  final anadidosClave = anadidos.map(diaClave).toSet();
  final quitadosClave = quitados.map(diaClave).toSet();

  // El día 0 del mes siguiente es el último de este.
  final ultimoDia = DateTime.utc(year, month + 1, 0).day;
  final libres = <DateTime>[];

  for (var dia = 1; dia <= ultimoDia; dia++) {
    final fecha = DateTime.utc(year, month, dia);
    if (fecha.isBefore(desde)) continue;
    if (quitadosClave.contains(fecha)) continue;

    final marcado =
        diasSemana.contains(fecha.weekday) || anadidosClave.contains(fecha);
    if (!marcado) continue;

    final ocupado = ocupacion[fecha] ?? OcupacionDia.libre;
    if (!ocupado.estaLibre) continue;

    libres.add(fecha);
  }
  return libres;
}

/// Mes con el que abrir la pantalla, como día 1.
///
/// [fecha] es la que llega por la ruta. Si falta o es de un mes ya pasado, se
/// abre el mes actual: la pantalla no deja ir hacia atrás.
DateTime mesInicial({DateTime? fecha, DateTime? hoy}) {
  final ahora = hoy ?? DateTime.now();
  final mesActual = DateTime.utc(ahora.year, ahora.month, 1);
  if (fecha == null) return mesActual;

  final mesPedido = DateTime.utc(fecha.year, fecha.month, 1);
  return mesPedido.isBefore(mesActual) ? mesActual : mesPedido;
}
