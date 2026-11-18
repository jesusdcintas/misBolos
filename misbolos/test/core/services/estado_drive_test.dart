import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/services/estado_drive.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('la marca de carpetas creadas', () {
    test('va por carpeta de trabajo', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await EstadoDriveStore.carpetasCreadas('raiz-A'), isFalse);
      await EstadoDriveStore.marcarCarpetasCreadas('raiz-A');
      expect(await EstadoDriveStore.carpetasCreadas('raiz-A'), isTrue);
      // Otra carpeta no hereda la marca de la primera.
      expect(await EstadoDriveStore.carpetasCreadas('raiz-B'), isFalse);
    });

    test('un id vacío no guarda ni cuenta como hecho', () async {
      SharedPreferences.setMockInitialValues({});

      await EstadoDriveStore.marcarCarpetasCreadas('   ');
      expect(await EstadoDriveStore.carpetasCreadas('   '), isFalse);
      expect(await EstadoDriveStore.carpetasCreadas(null), isFalse);
    });

    test('limpiarTodo olvida todas las carpetas, no otras claves', () async {
      SharedPreferences.setMockInitialValues({
        'otra_clave': true,
      });
      await EstadoDriveStore.marcarCarpetasCreadas('raiz-A');
      await EstadoDriveStore.marcarCarpetasCreadas('raiz-B');

      await EstadoDriveStore.limpiarTodo();

      expect(await EstadoDriveStore.carpetasCreadas('raiz-A'), isFalse);
      expect(await EstadoDriveStore.carpetasCreadas('raiz-B'), isFalse);
      // Lo que no es de las carpetas no se toca.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('otra_clave'), isTrue);
    });
  });
}
