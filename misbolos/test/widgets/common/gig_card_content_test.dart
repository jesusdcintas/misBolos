import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/theme/app_theme.dart';
import 'package:misbolos/models/franja_bolo.dart';
import 'package:misbolos/models/gig.dart';
import 'package:misbolos/widgets/common/gig_card_content.dart';

/// Un bolo privado de noche confirmado: las tres etiquetas a la vez.
Gig _boloPrivadoDeNoche() => Gig(
  fecha: DateTime(2026, 11, 14),
  clientId: 'cliente-1',
  cachet: 350,
  facturable: false,
  franja: FranjaBolo.noche,
  status: GigStatus.confirmadoB,
);

/// Ancho de un móvil pequeño.
const double _anchoMovil = 360;

Widget _app({required String nombre, Gig? gig, bool oscuro = false}) {
  return MaterialApp(
    theme: oscuro ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      body: SizedBox(
        width: _anchoMovil,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: GigCardContent(
              nombre: nombre,
              importe: '350,00 €',
              gig: gig ?? _boloPrivadoDeNoche(),
            ),
          ),
        ),
      ),
    ),
  );
}

/// StatusBadge pulsa con una animación infinita (PulsingBadge), así que
/// pumpAndSettle nunca asienta: se monta con un pump suelto.
Future<void> _montar(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump();
}

/// Desmonta y deja caducar el Future.delayed de 2 s que arranca el pulso,
/// para que no quede ningún Timer pendiente al cerrar el test.
Future<void> _desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  const nombreLargo =
      'La Marujona Fiestas y Eventos de la Sierra Sur de Sevilla';

  testWidgets('un nombre largo con las tres etiquetas no desborda', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(_anchoMovil, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _montar(tester, _app(nombre: 'La Marujona'));
    expect(tester.takeException(), isNull);
    await _desmontar(tester);
  });

  testWidgets('un nombre muy largo se corta en 2 líneas como máximo', (
    tester,
  ) async {
    await _montar(tester, _app(nombre: nombreLargo));

    final texto = tester.widget<Text>(find.text(nombreLargo));
    expect(texto.maxLines, 2);
    expect(texto.overflow, TextOverflow.ellipsis);

    final render = tester.renderObject<RenderParagraph>(find.text(nombreLargo));
    expect(render.size.height, lessThan(60), reason: 'más de dos líneas');
    await _desmontar(tester);
  });

  testWidgets('el nombre ocupa el ancho, no una columna estrecha', (
    tester,
  ) async {
    await _montar(tester, _app(nombre: 'La Marujona'));

    // Con las etiquetas en la misma fila al nombre le quedaban unos pocos
    // píxeles y se partía por sílabas.
    expect(tester.getSize(find.text('La Marujona')).width, greaterThan(150));
    await _desmontar(tester);
  });

  testWidgets('las etiquetas van debajo del nombre, no al lado', (
    tester,
  ) async {
    await _montar(tester, _app(nombre: 'La Marujona'));

    final yNombre = tester.getCenter(find.text('La Marujona')).dy;
    final yEtiqueta = tester.getCenter(find.text('Privado')).dy;
    expect(yEtiqueta, greaterThan(yNombre));
    await _desmontar(tester);
  });

  testWidgets('salen las tres etiquetas', (tester) async {
    await _montar(tester, _app(nombre: 'La Marujona'));

    expect(find.text('Privado'), findsOneWidget);
    expect(find.text('Noche'), findsOneWidget);
    expect(find.byType(GigBadges), findsOneWidget);
    await _desmontar(tester);
  });

  testWidgets('sin franja no se pinta su etiqueta', (tester) async {
    await _montar(
      tester,
      _app(
        nombre: 'La Marujona',
        gig: Gig(
          fecha: DateTime(2026, 11, 14),
          clientId: 'c1',
          facturable: false,
          status: GigStatus.confirmadoB,
        ),
      ),
    );

    expect(find.text('Noche'), findsNothing);
    expect(find.text('Tarde'), findsNothing);
    await _desmontar(tester);
  });

  testWidgets('tampoco desborda en modo oscuro', (tester) async {
    tester.view.physicalSize = const Size(_anchoMovil, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _montar(tester, _app(nombre: 'La Marujona', oscuro: true));
    expect(tester.takeException(), isNull);
    await _desmontar(tester);
  });
}
