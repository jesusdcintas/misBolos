import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/services/hapticos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Las llamadas que llegan al canal de plataforma.
  late List<String> llamadas;

  setUp(() {
    llamadas = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (llamada) async {
          if (llamada.method == 'HapticFeedback.vibrate') {
            llamadas.add('${llamada.arguments}');
          }
          return null;
        });
    // En los tests la plataforma es macOS, donde el servicio calla.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('con el interruptor apagado', () {
    setUp(() => Hapticos.fijarActivadosEnTests(false));

    test('seleccion no llama a nada', () {
      Hapticos.seleccion();
      expect(llamadas, isEmpty);
    });

    test('toque no llama a nada', () {
      Hapticos.toque();
      expect(llamadas, isEmpty);
    });

    test('umbral no llama a nada', () {
      Hapticos.umbral();
      expect(llamadas, isEmpty);
    });

    test('exito no llama a nada, ni siquiera el segundo golpe', () async {
      Hapticos.exito();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(llamadas, isEmpty);
    });

    test('error no llama a nada', () async {
      Hapticos.error();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(llamadas, isEmpty);
    });
  });

  group('con el interruptor encendido', () {
    setUp(() => Hapticos.fijarActivadosEnTests(true));

    test('seleccion llama una vez', () {
      Hapticos.seleccion();
      expect(llamadas.length, 1);
    });

    test('toque llama una vez', () {
      Hapticos.toque();
      expect(llamadas.length, 1);
    });

    test('exito son dos golpes encadenados', () async {
      Hapticos.exito();
      expect(llamadas.length, 1, reason: 'el primero es inmediato');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(llamadas.length, 2, reason: 'el segundo llega después');
    });

    test('error son dos golpes iguales', () async {
      Hapticos.error();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(llamadas.length, 2);
    });
  });

  group('fuera del móvil', () {
    setUp(() {
      Hapticos.fijarActivadosEnTests(true);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    });

    test('no hay vibración en escritorio aunque esté encendida', () {
      expect(Hapticos.disponibles, isFalse);
      Hapticos.seleccion();
      Hapticos.toque();
      Hapticos.umbral();
      expect(llamadas, isEmpty);
    });
  });
}
