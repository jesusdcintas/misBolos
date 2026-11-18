import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/services/estado_tutorial.dart';
import 'package:misbolos/core/services/hapticos.dart';
import 'package:misbolos/core/theme/app_theme.dart';
import 'package:misbolos/providers/tutorial_provider.dart';
import 'package:misbolos/widgets/tutorial/bocadillo_tour.dart';
import 'package:misbolos/widgets/tutorial/boton_ayuda_tour.dart';
import 'package:misbolos/widgets/tutorial/tour.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _claveElemento = GlobalKey();

/// Una pantalla de mentira con un elemento que señalar y el botón de ayuda.
///
/// Con el movimiento reducido del sistema, que es como se prueba el camino
/// sin animaciones y además deja que `pumpAndSettle` termine.
Widget _pantalla() => ProviderScope(
  child: MediaQuery(
    data: const MediaQueryData(
      size: Size(800, 600),
      accessibleNavigation: false,
      disableAnimations: true,
    ),
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Pantalla'),
          actions: [
            BotonAyudaTour(
              tour: Tour.agenda,
              pasos: () => [
                PasoTour(clave: _claveElemento, texto: 'Esto es un elemento'),
              ],
            ),
          ],
        ),
        body: Center(
          child: SizedBox(key: _claveElemento, width: 120, height: 60),
        ),
      ),
    ),
  ),
);

Future<DatosTutorial> _estado(WidgetTester tester) {
  final contenedor = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold)),
  );
  return contenedor.read(tutorialProvider.future);
}

void main() {
  setUp(() {
    Hapticos.fijarActivadosEnTests(false);
    // Alguien que ya vio el tour de Inicio y tiene los demás pendientes.
    SharedPreferences.setMockInitialValues({
      EstadoTutorial.claveInicializado: true,
      EstadoTutorial.claveVisto(Tour.inicio): true,
    });
  });

  testWidgets('ver el tutorial de una pantalla no toca el de las demás', (
    tester,
  ) async {
    await tester.pumpWidget(_pantalla());
    await tester.pumpAndSettle();

    final antes = await _estado(tester);
    expect(antes.vistos, {Tour.inicio});

    await tester.tap(find.byTooltip(textoAyudaTour));
    await tester.pumpAndSettle();
    expect(find.text('Esto es un elemento'), findsOneWidget);
    expect(find.text('1 de 1'), findsOneWidget);

    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Esto es un elemento'), findsNothing);

    // Ni se apunta el tour que se acaba de ver ni cambia ningún otro.
    final despues = await _estado(tester);
    expect(despues.vistos, {Tour.inicio});
    expect(despues.estaVisto(Tour.agenda), isFalse);
    expect(despues.decidido, isTrue);
    expect(despues.tarjetaOculta, antes.tarjetaOculta);
  });

  _testsSalida();

  testWidgets('saltarlo tampoco cambia nada', (tester) async {
    await tester.pumpWidget(_pantalla());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(textoAyudaTour));
    await tester.pumpAndSettle();
    // Hay dos «Saltar»: el del bocadillo y el del paquete, que está ahí
    // como red de seguridad por si el bocadillo no se ve.
    expect(find.text('Saltar'), findsNWidgets(2));
    await tester.tap(
      find.descendant(
        of: find.byType(BocadilloTour),
        matching: find.text('Saltar'),
      ),
    );
    await tester.pumpAndSettle();

    expect((await _estado(tester)).vistos, {Tour.inicio});
  });
}

/// Lo que no puede volver a pasar: que el tour deje la pantalla muerta.
void _testsSalida() {
  testWidgets('tocar fuera del bocadillo cierra el tour', (tester) async {
    await tester.pumpWidget(_pantalla());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(textoAyudaTour));
    await tester.pumpAndSettle();
    expect(find.byType(BocadilloTour), findsOneWidget);

    // Una esquina cualquiera, lejos del elemento señalado.
    await tester.tapAt(const Offset(20, 120));
    await tester.pumpAndSettle();

    expect(find.byType(BocadilloTour), findsNothing);
  });

  testWidgets('el primer paso no ofrece «Anterior»', (tester) async {
    await tester.pumpWidget(_pantalla());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(textoAyudaTour));
    await tester.pumpAndSettle();

    expect(find.text('Anterior'), findsNothing);

    // Cerrarlo antes de salir: si no, el siguiente tour no podría abrirse,
    // porque solo puede haber uno en pantalla.
    await tester.tapAt(const Offset(20, 120));
    await tester.pumpAndSettle();
  });
}
