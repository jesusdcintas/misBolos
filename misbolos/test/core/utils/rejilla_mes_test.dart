import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/utils/rejilla_mes.dart';

/// Columnas de una semana que empieza en lunes.
const _lun = 0;
const _mar = 1;
const _mie = 2;
const _jue = 3;
const _vie = 4;
const _sab = 5;
const _dom = 6;

void main() {
  group('huecosAntesDelDiaUno', () {
    test('un mes que empieza en lunes no lleva huecos', () {
      // Junio de 2026 empieza en lunes.
      expect(huecosAntesDelDiaUno(2026, 6), 0);
    });

    test('un mes que empieza en domingo lleva seis', () {
      // Noviembre de 2026 empieza en domingo.
      expect(huecosAntesDelDiaUno(2026, 11), 6);
    });

    test('un mes que empieza en miércoles lleva dos', () {
      // Abril de 2026 empieza en miércoles.
      expect(huecosAntesDelDiaUno(2026, 4), 2);
    });

    test('un mes que empieza en sábado lleva cinco', () {
      // Agosto de 2026 empieza en sábado.
      expect(huecosAntesDelDiaUno(2026, 8), 5);
    });

    test('nunca llega a siete', () {
      for (var year = 2024; year <= 2030; year++) {
        for (var month = 1; month <= 12; month++) {
          final huecos = huecosAntesDelDiaUno(year, month);
          expect(huecos, inInclusiveRange(0, 6), reason: '$year-$month');
        }
      }
    });
  });

  group('diaEnCelda: el día 1 va en su columna', () {
    test('junio de 2026: el 1 en la primera celda', () {
      expect(diaEnCelda(year: 2026, month: 6, indice: 0), 1);
      expect(columnaDelDia(2026, 6, 1), _lun);
    });

    test('noviembre de 2026: el 1 en la columna del domingo', () {
      // Las seis primeras celdas están vacías y el 1 es la séptima.
      for (var indice = 0; indice < 6; indice++) {
        expect(
          diaEnCelda(year: 2026, month: 11, indice: indice),
          isNull,
          reason: 'la celda $indice debería estar vacía',
        );
      }
      expect(diaEnCelda(year: 2026, month: 11, indice: 6), 1);
      expect(columnaDelDia(2026, 11, 1), _dom);
    });

    test('abril de 2026: el 1 en la columna del miércoles', () {
      expect(diaEnCelda(year: 2026, month: 4, indice: 2), 1);
      expect(columnaDelDia(2026, 4, 1), _mie);
    });

    test('agosto de 2026: el 1 en la columna del sábado', () {
      expect(diaEnCelda(year: 2026, month: 8, indice: 5), 1);
      expect(columnaDelDia(2026, 8, 1), _sab);
    });
  });

  group('diaEnCelda: no hay fila vacía al principio', () {
    test('la primera fila siempre tiene algún día', () {
      for (var year = 2024; year <= 2030; year++) {
        for (var month = 1; month <= 12; month++) {
          final primeraFila = [
            for (var indice = 0; indice < 7; indice++)
              diaEnCelda(year: year, month: month, indice: indice),
          ];
          expect(
            primeraFila.any((d) => d != null),
            isTrue,
            reason: '$year-$month no pinta ningún día en la primera fila',
          );
        }
      }
    });
  });

  group('columnaDelDia: el caso del fallo', () {
    test('el viernes 13 de noviembre de 2026 va bajo el viernes', () {
      expect(columnaDelDia(2026, 11, 13), _vie);
    });

    test('el martes 10 de noviembre de 2026 va bajo el martes', () {
      expect(columnaDelDia(2026, 11, 10), _mar);
    });

    test('el sábado 14 de noviembre de 2026 va bajo el sábado', () {
      expect(columnaDelDia(2026, 11, 14), _sab);
    });

    test('la columna coincide siempre con el día real de la semana', () {
      for (var dia = 1; dia <= 30; dia++) {
        expect(
          columnaDelDia(2026, 11, dia),
          DateTime.utc(2026, 11, dia).weekday - 1,
          reason: 'el día $dia cae en otra columna',
        );
      }
    });

    test('el jueves 1 de enero de 2026 va bajo el jueves', () {
      expect(columnaDelDia(2026, 1, 1), _jue);
    });
  });

  group('filasDelMes', () {
    test('febrero de 2027: 28 días desde el lunes, cuatro filas justas', () {
      expect(huecosAntesDelDiaUno(2027, 2), 0);
      expect(ultimoDiaDelMes(2027, 2), 28);
      expect(filasDelMes(2027, 2), 4);
    });

    test('febrero de 2027: el 28 entra en la última celda', () {
      expect(diaEnCelda(year: 2027, month: 2, indice: 27), 28);
    });

    test('noviembre de 2026 necesita seis filas', () {
      expect(filasDelMes(2026, 11), 6);
    });

    test('junio de 2026 necesita cinco', () {
      expect(filasDelMes(2026, 6), 5);
    });

    test('todos los días del mes caben en las filas calculadas', () {
      for (var year = 2024; year <= 2030; year++) {
        for (var month = 1; month <= 12; month++) {
          final celdas = filasDelMes(year, month) * 7;
          final pintados = <int>{};
          for (var indice = 0; indice < celdas; indice++) {
            final dia = diaEnCelda(year: year, month: month, indice: indice);
            if (dia != null) pintados.add(dia);
          }
          expect(
            pintados.length,
            ultimoDiaDelMes(year, month),
            reason: 'faltan días en $year-$month',
          );
        }
      }
    });
  });
}
