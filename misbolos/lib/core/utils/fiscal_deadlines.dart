import 'package:flutter/foundation.dart';

import 'date_formatter.dart';

const _nombresMes = [
  '',
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Plazo de presentación del pago fraccionado de IRPF (modelo 130).
@immutable
class PlazoModelo130 {
  /// Trimestre que se declara. Null en el modo Año.
  final int? trimestre;

  /// Último día para presentarlo. Null en el modo Año.
  final DateTime? limite;

  /// Días que faltan. Negativo si el plazo ya pasó. Null en el modo Año.
  final int? diasRestantes;

  /// El plazo ya se ha cerrado.
  final bool cerrado;

  /// Línea lista para mostrar.
  final String texto;

  const PlazoModelo130({
    this.trimestre,
    this.limite,
    this.diasRestantes,
    this.cerrado = false,
    required this.texto,
  });
}

/// Último día para presentar el modelo 130 del trimestre [quarter] de [year].
///
/// 1T, 2T y 3T se presentan del 1 al 20 del mes siguiente al cierre; el 4T, del
/// 1 al 30 de enero del año siguiente.
DateTime limiteModelo130(int year, int quarter) {
  assert(quarter >= 1 && quarter <= 4);
  switch (quarter) {
    case 1:
      return DateTime(year, 4, 20);
    case 2:
      return DateTime(year, 7, 20);
    case 3:
      return DateTime(year, 10, 20);
    default:
      return DateTime(year + 1, 1, 30);
  }
}

/// Resuelve el plazo del modelo 130 de un periodo.
///
/// [quarter] a null (modo Año) devuelve la nota de que son los cuatro
/// trimestres, sin plazo. [hoy] solo se pasa en los tests.
PlazoModelo130 resolverPlazoModelo130({
  required int year,
  int? quarter,
  DateTime? hoy,
}) {
  if (quarter == null) {
    return const PlazoModelo130(texto: 'Suma de los cuatro trimestres');
  }

  final limite = limiteModelo130(year, quarter);
  final ahora = hoy ?? DateTime.now();
  // La cuenta de días se hace en UTC: con fechas locales, el cambio de hora de
  // marzo y de octubre mete un día de 23 o 25 horas y inDays pierde un día.
  final limiteDia = DateTime.utc(limite.year, limite.month, limite.day);
  final hoyDia = DateTime.utc(ahora.year, ahora.month, ahora.day);
  final dias = limiteDia.difference(hoyDia).inDays;
  // El último día del plazo todavía cuenta como abierto.
  final cerrado = dias < 0;

  final String texto;
  if (cerrado) {
    texto =
        'Pago del ${quarter}T: plazo cerrado el '
        '${DateFormatter.display(limite)}';
  } else {
    final mes = _nombresMes[limite.month];
    final anio = limite.year != year ? ' de ${limite.year}' : '';
    final restante = dias == 0
        ? 'último día'
        : 'faltan $dias día${dias == 1 ? '' : 's'}';
    texto =
        'Pago del ${quarter}T: del 1 al ${limite.day} de $mes$anio '
        '· $restante';
  }

  return PlazoModelo130(
    trimestre: quarter,
    limite: limite,
    diasRestantes: dias,
    cerrado: cerrado,
    texto: texto,
  );
}
