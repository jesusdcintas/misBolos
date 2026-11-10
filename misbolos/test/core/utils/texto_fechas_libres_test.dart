import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:misbolos/core/utils/texto_fechas_libres.dart';

void main() {
  setUpAll(() async {
    // La misma inicialización que hace main.dart.
    await initializeDateFormatting('es_ES', null);
  });

  group('lineaDeFecha', () {
    test('escribe el día de la semana con mayúscula inicial', () {
      expect(lineaDeFecha(DateTime.utc(2026, 10, 2)), 'Viernes 2 de octubre');
    });

    test('mantiene las tildes', () {
      expect(lineaDeFecha(DateTime.utc(2026, 10, 7)), 'Miércoles 7 de octubre');
      expect(lineaDeFecha(DateTime.utc(2026, 10, 10)), 'Sábado 10 de octubre');
    });

    test('el mes va en minúscula', () {
      expect(lineaDeFecha(DateTime.utc(2026, 1, 5)), 'Lunes 5 de enero');
      expect(
        lineaDeFecha(DateTime.utc(2026, 12, 25)),
        'Viernes 25 de diciembre',
      );
    });

    test('no rellena el día con un cero delante', () {
      expect(lineaDeFecha(DateTime.utc(2026, 10, 3)), 'Sábado 3 de octubre');
    });

    test('da igual la hora de la fecha', () {
      expect(
        lineaDeFecha(DateTime.utc(2026, 10, 2, 23, 45)),
        'Viernes 2 de octubre',
      );
    });
  });

  group('nombreDeMes', () {
    test('devuelve el mes en minúscula', () {
      expect(nombreDeMes(2026, 10), 'octubre');
      expect(nombreDeMes(2026, 3), 'marzo');
      expect(nombreDeMes(2026, 8), 'agosto');
    });
  });

  group('textoFechasLibres', () {
    final fechas = [
      DateTime.utc(2026, 10, 2),
      DateTime.utc(2026, 10, 3),
      DateTime.utc(2026, 10, 9),
      DateTime.utc(2026, 10, 10),
    ];

    test('con cabecera, como en el ejemplo', () {
      expect(textoFechasLibres(fechas, year: 2026, month: 10), '''
Fechas libres en octubre:
Viernes 2 de octubre
Sábado 3 de octubre
Viernes 9 de octubre
Sábado 10 de octubre''');
    });

    test('sin cabecera, solo las líneas', () {
      expect(
        textoFechasLibres(fechas, year: 2026, month: 10, cabecera: false),
        '''
Viernes 2 de octubre
Sábado 3 de octubre
Viernes 9 de octubre
Sábado 10 de octubre''',
      );
    });

    test('una sola fecha', () {
      expect(
        textoFechasLibres([fechas.first], year: 2026, month: 10),
        'Fechas libres en octubre:\nViernes 2 de octubre',
      );
    });

    test('sin fechas avisa y no pone cabecera', () {
      const aviso = 'No tienes fechas libres con estos días';
      expect(textoFechasLibres(const [], year: 2026, month: 10), aviso);
      expect(
        textoFechasLibres(const [], year: 2026, month: 10, cabecera: false),
        aviso,
      );
    });

    test('la cabecera usa el mes pedido, no el de las fechas', () {
      final texto = textoFechasLibres(
        [DateTime.utc(2026, 11, 1)],
        year: 2026,
        month: 11,
      );
      expect(texto, startsWith('Fechas libres en noviembre:'));
    });
  });
}
