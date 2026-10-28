import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/config/features.dart';

void main() {
  group('kIaHabilitada', () {
    test('la IA viene deshabilitada por defecto', () {
      // Sin --dart-define=IA_HABILITADA=true la IA no debe mostrarse.
      expect(kIaHabilitada, isFalse);
    });
  });

  group('esRutaDeIa', () {
    test('reconoce la ruta del asistente', () {
      expect(esRutaDeIa('/assistant'), isTrue);
    });

    test('reconoce subrutas del asistente', () {
      expect(esRutaDeIa('/assistant/historial'), isTrue);
    });

    test('no bloquea las rutas normales de la app', () {
      expect(esRutaDeIa('/'), isFalse);
      expect(esRutaDeIa('/calendar'), isFalse);
      expect(esRutaDeIa('/finanzas'), isFalse);
      expect(esRutaDeIa('/profile'), isFalse);
      expect(esRutaDeIa('/settings'), isFalse);
      expect(esRutaDeIa('/login'), isFalse);
    });
  });
}
