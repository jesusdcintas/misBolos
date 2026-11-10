import 'package:intl/intl.dart';

import 'fechas_libres.dart';

final _diaSemana = DateFormat('EEEE', 'es');
final _mes = DateFormat('MMMM', 'es');

String _conMayusculaInicial(String texto) =>
    texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);

/// Nombre del mes en minúscula, por ejemplo `octubre`.
String nombreDeMes(int year, int month) =>
    _mes.format(DateTime.utc(year, month, 1)).toLowerCase();

/// Una fecha, por ejemplo `Miércoles 7 de octubre`.
///
/// El día de la semana lleva la primera letra en mayúscula y el mes va en
/// minúscula. Los nombres salen de la localización `es` de intl.
String lineaDeFecha(DateTime fecha) {
  final dia = _conMayusculaInicial(_diaSemana.format(fecha).toLowerCase());
  final mes = _mes.format(fecha).toLowerCase();
  return '$dia ${fecha.day} de $mes';
}

/// Cabecera según la franja pedida.
String cabeceraDeFranja(FranjaPedida pedida, int year, int month) {
  final mes = nombreDeMes(year, month);
  return switch (pedida) {
    FranjaPedida.ambas => 'Fechas libres en $mes:',
    FranjaPedida.soloTardes => 'Tardes libres en $mes:',
    FranjaPedida.soloNoches => 'Noches libres en $mes:',
  };
}

/// Una línea del texto.
///
/// Pidiendo ambas franjas, un día con solo media libre lleva el sufijo
/// `(tarde)` o `(noche)`. Pidiendo solo tardes o solo noches no se indica:
/// ya lo dice la cabecera.
String lineaDeDiaLibre(DiaLibre dia, FranjaPedida pedida) {
  final base = lineaDeFecha(dia.fecha);
  if (pedida != FranjaPedida.ambas || dia.completo) return base;
  return dia.tarde ? '$base (tarde)' : '$base (noche)';
}

/// Texto de las fechas libres, listo para copiar o compartir.
///
/// Con [cabecera] empieza por la cabecera de [pedida]. Sin ninguna fecha
/// devuelve el aviso de que no hay, sin cabecera.
String textoFechasLibres(
  List<DiaLibre> dias, {
  required int year,
  required int month,
  FranjaPedida pedida = FranjaPedida.ambas,
  bool cabecera = true,
}) {
  if (dias.isEmpty) return 'No tienes fechas libres con estos días';

  final lineas = dias.map((d) => lineaDeDiaLibre(d, pedida)).toList();
  if (cabecera) {
    lineas.insert(0, cabeceraDeFranja(pedida, year, month));
  }
  return lineas.join('\n');
}
