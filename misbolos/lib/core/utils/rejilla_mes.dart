// Colocación de los días de un mes en una rejilla de siete columnas que
// empieza en lunes. Las celdas se numeran de 0 en adelante, por filas.

/// Último día del mes.
int ultimoDiaDelMes(int year, int month) => DateTime.utc(year, month + 1, 0).day;

/// Celdas vacías antes del día 1.
///
/// `weekday` va de 1 (lunes) a 7 (domingo), así que los huecos son de 0 a 6:
/// un mes que empieza en lunes no lleva ninguno y uno que empieza en domingo
/// lleva seis.
int huecosAntesDelDiaUno(int year, int month) =>
    DateTime.utc(year, month, 1).weekday - 1;

/// Filas que necesita el mes.
int filasDelMes(int year, int month) {
  final celdas = huecosAntesDelDiaUno(year, month) + ultimoDiaDelMes(year, month);
  return (celdas / 7).ceil();
}

/// Día que va en la celda [indice], o null si la celda está vacía.
///
/// El día 1 cae en la celda [huecosAntesDelDiaUno], así que hay que sumar 1 al
/// pasar del índice de celda, que empieza en 0, al número de día, que empieza
/// en 1.
int? diaEnCelda({
  required int year,
  required int month,
  required int indice,
}) {
  final dia = indice - huecosAntesDelDiaUno(year, month) + 1;
  if (dia < 1 || dia > ultimoDiaDelMes(year, month)) return null;
  return dia;
}

/// Columna en la que cae un día: 0 lunes … 6 domingo.
int columnaDelDia(int year, int month, int dia) =>
    (huecosAntesDelDiaUno(year, month) + dia - 1) % 7;
