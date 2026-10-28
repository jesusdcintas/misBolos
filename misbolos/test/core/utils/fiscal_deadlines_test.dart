import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/utils/fiscal_deadlines.dart';

void main() {
  group('limiteModelo130', () {
    test('1T vence el 20 de abril del mismo año', () {
      expect(limiteModelo130(2026, 1), DateTime(2026, 4, 20));
    });

    test('2T vence el 20 de julio del mismo año', () {
      expect(limiteModelo130(2026, 2), DateTime(2026, 7, 20));
    });

    test('3T vence el 20 de octubre del mismo año', () {
      expect(limiteModelo130(2026, 3), DateTime(2026, 10, 20));
    });

    test('4T vence el 30 de enero del año siguiente', () {
      expect(limiteModelo130(2026, 4), DateTime(2027, 1, 30));
    });
  });

  group('resolverPlazoModelo130: un mes de cada trimestre', () {
    test('febrero declara en el 1T', () {
      final plazo = resolverPlazoModelo130(
        year: 2026,
        quarter: 1,
        hoy: DateTime(2026, 2, 15),
      );
      expect(plazo.trimestre, 1);
      expect(plazo.limite, DateTime(2026, 4, 20));
      expect(plazo.cerrado, isFalse);
      expect(plazo.texto, contains('Pago del 1T'));
      expect(plazo.texto, contains('del 1 al 20 de abril'));
      expect(plazo.texto, contains('faltan 64 días'));
    });

    test('mayo declara en el 2T', () {
      final plazo = resolverPlazoModelo130(
        year: 2026,
        quarter: 2,
        hoy: DateTime(2026, 5, 10),
      );
      expect(plazo.trimestre, 2);
      expect(plazo.limite, DateTime(2026, 7, 20));
      expect(plazo.texto, contains('del 1 al 20 de julio'));
      expect(plazo.cerrado, isFalse);
    });

    test('agosto declara en el 3T', () {
      final plazo = resolverPlazoModelo130(
        year: 2026,
        quarter: 3,
        hoy: DateTime(2026, 8, 1),
      );
      expect(plazo.trimestre, 3);
      expect(plazo.limite, DateTime(2026, 10, 20));
      expect(plazo.texto, contains('del 1 al 20 de octubre'));
    });

    test('noviembre declara en el 4T, en enero del año siguiente', () {
      final plazo = resolverPlazoModelo130(
        year: 2026,
        quarter: 4,
        hoy: DateTime(2026, 11, 20),
      );
      expect(plazo.trimestre, 4);
      expect(plazo.limite, DateTime(2027, 1, 30));
      expect(plazo.cerrado, isFalse);
      expect(plazo.texto, contains('del 1 al 30 de enero de 2027'));
      expect(plazo.diasRestantes, 71);
    });
  });

  group('resolverPlazoModelo130: plazos cerrados', () {
    test('un plazo pasado se marca cerrado con su fecha', () {
      final plazo = resolverPlazoModelo130(
        year: 2026,
        quarter: 1,
        hoy: DateTime(2026, 6, 1),
      );
      expect(plazo.cerrado, isTrue);
      expect(plazo.texto, 'Pago del 1T: plazo cerrado el 20/04/2026');
      expect(plazo.diasRestantes, lessThan(0));
    });

    test('el 4T se cierra pasado el 30 de enero siguiente', () {
      final abierto = resolverPlazoModelo130(
        year: 2026,
        quarter: 4,
        hoy: DateTime(2027, 1, 29),
      );
      expect(abierto.cerrado, isFalse);
      expect(abierto.diasRestantes, 1);

      final cerrado = resolverPlazoModelo130(
        year: 2026,
        quarter: 4,
        hoy: DateTime(2027, 1, 31),
      );
      expect(cerrado.cerrado, isTrue);
      expect(cerrado.texto, 'Pago del 4T: plazo cerrado el 30/01/2027');
    });

    test('el último día del plazo todavía está abierto', () {
      final plazo = resolverPlazoModelo130(
        year: 2026,
        quarter: 1,
        hoy: DateTime(2026, 4, 20),
      );
      expect(plazo.cerrado, isFalse);
      expect(plazo.diasRestantes, 0);
      expect(plazo.texto, contains('último día'));
    });

    test('la hora de hoy no adelanta el cierre', () {
      final plazo = resolverPlazoModelo130(
        year: 2026,
        quarter: 1,
        hoy: DateTime(2026, 4, 20, 23, 59),
      );
      expect(plazo.cerrado, isFalse);
      expect(plazo.diasRestantes, 0);
    });

    test('faltan 1 día se escribe en singular', () {
      final plazo = resolverPlazoModelo130(
        year: 2026,
        quarter: 1,
        hoy: DateTime(2026, 4, 19),
      );
      expect(plazo.texto, contains('faltan 1 día'));
      expect(plazo.texto, isNot(contains('1 días')));
    });
  });

  group('resolverPlazoModelo130: modo Año', () {
    test('no tiene plazo y lo dice', () {
      final plazo = resolverPlazoModelo130(year: 2026, hoy: DateTime(2026, 3, 1));
      expect(plazo.trimestre, isNull);
      expect(plazo.limite, isNull);
      expect(plazo.diasRestantes, isNull);
      expect(plazo.cerrado, isFalse);
      expect(plazo.texto, 'Suma de los cuatro trimestres');
    });
  });
}
