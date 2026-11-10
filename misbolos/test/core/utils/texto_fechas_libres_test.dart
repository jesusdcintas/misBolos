import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:misbolos/core/utils/fechas_libres.dart';
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
      for (final dia in [2, 3, 9, 10])
        DiaLibre(fecha: DateTime.utc(2026, 10, dia), tarde: true, noche: true),
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
        [
          DiaLibre(
            fecha: DateTime.utc(2026, 11, 1),
            tarde: true,
            noche: true,
          ),
        ],
        year: 2026,
        month: 11,
      );
      expect(texto, startsWith('Fechas libres en noviembre:'));
    });
  });
  group('cabeceraDeFranja', () {
    test('cada franja tiene su cabecera', () {
      expect(
        cabeceraDeFranja(FranjaPedida.ambas, 2026, 11),
        'Fechas libres en noviembre:',
      );
      expect(
        cabeceraDeFranja(FranjaPedida.soloTardes, 2026, 11),
        'Tardes libres en noviembre:',
      );
      expect(
        cabeceraDeFranja(FranjaPedida.soloNoches, 2026, 11),
        'Noches libres en noviembre:',
      );
    });
  });

  group('lineaDeDiaLibre', () {
    final completo = DiaLibre(
      fecha: DateTime.utc(2026, 11, 14),
      tarde: true,
      noche: true,
    );
    final soloTarde = DiaLibre(
      fecha: DateTime.utc(2026, 11, 14),
      tarde: true,
      noche: false,
    );
    final soloNoche = DiaLibre(
      fecha: DateTime.utc(2026, 11, 14),
      tarde: false,
      noche: true,
    );

    test('pidiendo ambas, un día entero libre no lleva sufijo', () {
      expect(
        lineaDeDiaLibre(completo, FranjaPedida.ambas),
        'Sábado 14 de noviembre',
      );
    });

    test('pidiendo ambas, media tarde libre lleva (tarde)', () {
      expect(
        lineaDeDiaLibre(soloTarde, FranjaPedida.ambas),
        'Sábado 14 de noviembre (tarde)',
      );
    });

    test('pidiendo ambas, media noche libre lleva (noche)', () {
      expect(
        lineaDeDiaLibre(soloNoche, FranjaPedida.ambas),
        'Sábado 14 de noviembre (noche)',
      );
    });

    test('pidiendo solo tardes no se indica la franja', () {
      expect(
        lineaDeDiaLibre(soloTarde, FranjaPedida.soloTardes),
        'Sábado 14 de noviembre',
      );
    });

    test('pidiendo solo noches no se indica la franja', () {
      expect(
        lineaDeDiaLibre(soloNoche, FranjaPedida.soloNoches),
        'Sábado 14 de noviembre',
      );
    });
  });

  group('textoFechasLibres por franja', () {
    final dias = [
      DiaLibre(fecha: DateTime.utc(2026, 11, 13), tarde: true, noche: false),
      DiaLibre(fecha: DateTime.utc(2026, 11, 14), tarde: true, noche: true),
      DiaLibre(fecha: DateTime.utc(2026, 11, 20), tarde: false, noche: true),
    ];

    test('ambas: cabecera de fechas y sufijos en los parciales', () {
      expect(textoFechasLibres(dias, year: 2026, month: 11), """
Fechas libres en noviembre:
Viernes 13 de noviembre (tarde)
Sábado 14 de noviembre
Viernes 20 de noviembre (noche)""");
    });

    test('solo tardes: cabecera de tardes y sin sufijos', () {
      expect(
        textoFechasLibres(
          dias.where((d) => d.tarde).toList(),
          year: 2026,
          month: 11,
          pedida: FranjaPedida.soloTardes,
        ),
        """
Tardes libres en noviembre:
Viernes 13 de noviembre
Sábado 14 de noviembre""",
      );
    });

    test('solo noches: cabecera de noches y sin sufijos', () {
      expect(
        textoFechasLibres(
          dias.where((d) => d.noche).toList(),
          year: 2026,
          month: 11,
          pedida: FranjaPedida.soloNoches,
        ),
        """
Noches libres en noviembre:
Sábado 14 de noviembre
Viernes 20 de noviembre""",
      );
    });

    test('sin cabecera, los sufijos de ambas se mantienen', () {
      expect(
        textoFechasLibres(dias, year: 2026, month: 11, cabecera: false),
        """
Viernes 13 de noviembre (tarde)
Sábado 14 de noviembre
Viernes 20 de noviembre (noche)""",
      );
    });

    test('sin días, el aviso es el mismo en los tres modos', () {
      for (final pedida in FranjaPedida.values) {
        expect(
          textoFechasLibres(const [], year: 2026, month: 11, pedida: pedida),
          'No tienes fechas libres con estos días',
        );
      }
    });
  });
}
