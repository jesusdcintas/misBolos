import 'package:intl/intl.dart';

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

/// Texto de las fechas libres, listo para copiar o compartir.
///
/// Con [cabecera] empieza por `Fechas libres en <mes>:`. Sin ninguna fecha
/// devuelve el aviso de que no hay, sin cabecera.
String textoFechasLibres(
  List<DateTime> fechas, {
  required int year,
  required int month,
  bool cabecera = true,
}) {
  if (fechas.isEmpty) return 'No tienes fechas libres con estos días';

  final lineas = fechas.map(lineaDeFecha).toList();
  if (cabecera) {
    lineas.insert(0, 'Fechas libres en ${nombreDeMes(year, month)}:');
  }
  return lineas.join('\n');
}
