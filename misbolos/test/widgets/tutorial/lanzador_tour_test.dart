import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/services/estado_tutorial.dart';
import 'package:misbolos/core/services/hapticos.dart';
import 'package:misbolos/core/theme/app_theme.dart';
import 'package:misbolos/widgets/tutorial/bocadillo_tour.dart';
import 'package:misbolos/widgets/tutorial/boton_ayuda_tour.dart';
import 'package:misbolos/widgets/tutorial/lanzador_tour.dart';
import 'package:misbolos/widgets/tutorial/tour.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _claveBoton = GlobalKey();
final _navegador = GlobalKey<NavigatorState>();

/// Una pantalla de mentira cuyo botón señalado abre una hoja con un campo.
///
/// Reproduce el fallo del simulador: el tour señalaba el botón de «Datos de
/// facturación» y su velo, en el overlay raíz, se quedaba por encima del panel
/// comiéndose los toques, así que no se podía escribir.
Widget _pantallaConHoja() => ProviderScope(
  child: MediaQuery(
    data: const MediaQueryData(
      size: Size(800, 600),
      disableAnimations: true,
    ),
    child: MaterialApp(
      navigatorKey: _navegador,
      // Igual que el router de la app: cierra el tour si se abre algo encima.
      navigatorObservers: [ObservadorTour()],
      theme: AppTheme.light,
      home: Scaffold(
        appBar: AppBar(
          actions: [
            BotonAyudaTour(
              tour: Tour.perfil,
              pasos: () => [
                PasoTour(clave: _claveBoton, texto: 'Abre tus datos'),
              ],
            ),
          ],
        ),
        body: Center(
          child: ElevatedButton(
            key: _claveBoton,
            onPressed: () => _abrirHoja(_navegador.currentContext!),
            child: const Text('Datos de facturación'),
          ),
        ),
      ),
    ),
  ),
);

void _abrirHoja(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (_) => const Padding(
      padding: EdgeInsets.all(24),
      child: TextField(
        decoration: InputDecoration(labelText: 'NIF'),
      ),
    ),
  );
}

Future<void> _abrirTour(WidgetTester tester) async {
  await tester.tap(find.byTooltip(textoAyudaTour));
  await tester.pumpAndSettle();
  expect(find.byType(BocadilloTour), findsOneWidget);
}

void main() {
  setUp(() {
    Hapticos.fijarActivadosEnTests(false);
    SharedPreferences.setMockInitialValues({
      EstadoTutorial.claveInicializado: true,
      EstadoTutorial.claveVisto(Tour.inicio): true,
    });
  });

  testWidgets('tocar el elemento señalado cierra el tour', (tester) async {
    await tester.pumpWidget(_pantallaConHoja());
    await tester.pumpAndSettle();

    await _abrirTour(tester);

    // Tocar el propio botón señalado termina el tour (onClickTarget), para que
    // el usuario pueda usar lo que el tour le enseña sin pelear con el velo.
    // El toque lo intercepta el velo sobre el objetivo (de ahí warnIfMissed),
    // que es justo lo que dispara onClickTarget.
    await tester.tap(find.byKey(_claveBoton), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(BocadilloTour), findsNothing);
  });

  testWidgets(
    'si se abre una hoja con el tour puesto, el tour se cierra y el campo '
    'acepta texto',
    (tester) async {
      await tester.pumpWidget(_pantallaConHoja());
      await tester.pumpAndSettle();

      await _abrirTour(tester);

      // Algo abre una hoja mientras el tour está activo: el ObservadorTour lo
      // cierra en cuanto se empuja la ruta.
      _abrirHoja(_navegador.currentContext!);
      await tester.pumpAndSettle();

      expect(find.byType(BocadilloTour), findsNothing);

      // Y, ya sin velo, el campo del panel acepta texto.
      await tester.enterText(find.byType(TextField), '12345678Z');
      await tester.pump();
      expect(find.text('12345678Z'), findsOneWidget);
    },
  );
}
