import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/models/app_settings.dart';

void main() {
  group('AppSettings.irpfDefault', () {
    test('el 0 % sobrevive a la ida y vuelta toMap -> fromMap', () {
      final original = AppSettings(irpfDefault: 0.0);
      final recuperado = AppSettings.fromMap(original.toMap());
      expect(recuperado.irpfDefault, 0.0);
    });

    test('el 7 % y el 15 % también sobreviven', () {
      expect(
        AppSettings.fromMap(AppSettings(irpfDefault: 0.07).toMap()).irpfDefault,
        0.07,
      );
      expect(
        AppSettings.fromMap(AppSettings(irpfDefault: 0.15).toMap()).irpfDefault,
        0.15,
      );
    });

    test('un 0 guardado como int no se confunde con ausencia de valor', () {
      // SQLite puede devolver un 0 entero en una columna REAL.
      final recuperado = AppSettings.fromMap({'irpf_default': 0});
      expect(recuperado.irpfDefault, 0.0);
    });

    test('solo se usa el 15 % por defecto si no hay valor guardado', () {
      expect(AppSettings.fromMap(const {}).irpfDefault, 0.15);
      expect(AppSettings.fromMap({'irpf_default': null}).irpfDefault, 0.15);
    });

    test('copyWith no pisa el 0 % con el valor anterior', () {
      final conCero = AppSettings(irpfDefault: 0.15).copyWith(irpfDefault: 0.0);
      expect(conCero.irpfDefault, 0.0);
    });

    test('toMap guarda el 0 % explícitamente', () {
      expect(AppSettings(irpfDefault: 0.0).toMap()['irpf_default'], 0.0);
    });
  });
}
