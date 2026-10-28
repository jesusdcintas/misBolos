import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/config/fiscal.dart';

void main() {
  group('RetencionIrpf.opciones', () {
    test('son 15 %, 7 % y 0 %', () {
      expect(RetencionIrpf.opciones, [0.0, 0.07, 0.15]);
    });

    test('el 19 % ya no es una opción', () {
      expect(RetencionIrpf.opciones.contains(0.19), isFalse);
      expect(RetencionIrpf.esValida(0.19), isFalse);
    });

    test('esValida acepta las tres opciones', () {
      expect(RetencionIrpf.esValida(0.0), isTrue);
      expect(RetencionIrpf.esValida(0.07), isTrue);
      expect(RetencionIrpf.esValida(0.15), isTrue);
    });
  });

  group('RetencionIrpf.etiqueta', () {
    test('formatea el porcentaje sin decimales', () {
      expect(RetencionIrpf.etiqueta(0.0), '0%');
      expect(RetencionIrpf.etiqueta(0.07), '7%');
      expect(RetencionIrpf.etiqueta(0.15), '15%');
    });
  });

  group('RetencionIrpf.explicacion', () {
    test('cada opción tiene explicación', () {
      for (final rate in RetencionIrpf.opciones) {
        expect(RetencionIrpf.explicacion(rate), isNotNull);
        expect(RetencionIrpf.explicacion(rate), isNotEmpty);
      }
    });

    test('un valor fuera de la lista no tiene explicación', () {
      expect(RetencionIrpf.explicacion(0.19), isNull);
      expect(RetencionIrpf.explicacion(0.21), isNull);
    });
  });
}
