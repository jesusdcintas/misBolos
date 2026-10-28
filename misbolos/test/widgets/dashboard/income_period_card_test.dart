import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/theme/app_theme.dart';
import 'package:misbolos/providers/stats_provider.dart';
import 'package:misbolos/widgets/dashboard/income_period_card.dart';

const _periodo = DashboardPeriod(
  mode: DashboardPeriodMode.anio,
  year: 2026,
  month: 10,
  quarter: 4,
);

/// Cifras reales del año 2026: 10.128 € cobrados, 4.997,40 € pendientes y
/// 15.925,40 € de total previsto.
PeriodDashboardStats _statsDe2026() => PeriodDashboardStats(
  cobradoFacturas: 10128,
  pendiente: 4997.40,
  previsto: 800,
  totalBolos: 12,
);

Widget _app(PeriodDashboardStats stats, {bool oscuro = false}) => MaterialApp(
  theme: oscuro ? AppTheme.dark : AppTheme.light,
  home: Scaffold(
    body: SizedBox(
      width: 400,
      child: IncomePeriodCard(stats: stats, period: _periodo),
    ),
  ),
);

/// Solo los ColoredBox de dentro de la barra: el Scaffold mete otro por su
/// cuenta y contarlo falsearía las medidas.
final _enLaBarra = find.descendant(
  of: find.byType(ClipRRect),
  matching: find.byType(ColoredBox),
);

/// Los tramos de la barra, por orden de aparición.
List<Size> _tramos(WidgetTester tester) {
  return tester
      .widgetList<ColoredBox>(_enLaBarra)
      .map((b) => tester.getSize(find.byWidget(b)))
      .toList();
}

void main() {
  testWidgets('las cifras del año 2026 salen en la tarjeta', (tester) async {
    await tester.pumpWidget(_app(_statsDe2026()));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Cobrado'), findsWidgets);
    expect(find.text('Pendiente de cobro'), findsOneWidget);
    expect(find.text('Total previsto'), findsOneWidget);
    expect(find.textContaining('12 bolos'), findsOneWidget);
  });

  group('barra de tramos', () {
    testWidgets('los tres tramos tienen alto visible, no 0', (tester) async {
      await tester.pumpWidget(_app(_statsDe2026()));
      await tester.pumpAndSettle();

      final tramos = _tramos(tester);
      expect(tramos.length, 3);
      for (final tramo in tramos) {
        expect(
          tramo.height,
          greaterThan(0),
          reason: 'un tramo sin alto hace invisible la barra',
        );
        expect(tramo.width, greaterThan(0));
      }
    });

    testWidgets('los anchos son proporcionales a cada importe', (tester) async {
      await tester.pumpWidget(_app(_statsDe2026()));
      await tester.pumpAndSettle();

      final tramos = _tramos(tester);
      final ancho = tramos.fold<double>(0, (s, t) => s + t.width);
      // 10.128 de 15.925,40 es el 63,6 %.
      expect(tramos[0].width / ancho, closeTo(0.636, 0.01));
      // 4.997,40 de 15.925,40 es el 31,4 %.
      expect(tramos[1].width / ancho, closeTo(0.314, 0.01));
      // Lo que queda, 800, es el 5 %.
      expect(tramos[2].width / ancho, closeTo(0.050, 0.01));
    });

    testWidgets('un periodo sin datos deja la barra vacía sin tramos', (
      tester,
    ) async {
      await tester.pumpWidget(_app(PeriodDashboardStats()));
      await tester.pumpAndSettle();
      expect(_enLaBarra, findsNothing);
    });

    testWidgets('si todo está cobrado hay un solo tramo', (tester) async {
      await tester.pumpWidget(
        _app(PeriodDashboardStats(cobradoFacturas: 5000)),
      );
      await tester.pumpAndSettle();

      final tramos = _tramos(tester);
      expect(tramos.length, 1);
      expect(tramos.first.height, greaterThan(0));
    });

    testWidgets('también se ve en modo oscuro', (tester) async {
      await tester.pumpWidget(_app(_statsDe2026(), oscuro: true));
      await tester.pumpAndSettle();

      final tramos = _tramos(tester);
      expect(tramos.length, 3);
      for (final tramo in tramos) {
        expect(tramo.height, greaterThan(0));
      }
    });
  });

  group('leyenda', () {
    testWidgets('cada punto lleva el color de su tramo', (tester) async {
      await tester.pumpWidget(_app(_statsDe2026()));
      await tester.pumpAndSettle();

      expect(find.text('Cobrado'), findsWidgets);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Confirmado sin facturar'), findsOneWidget);

      // Los colores de los tramos y los de los puntos son los mismos.
      final coloresTramo = tester
          .widgetList<ColoredBox>(_enLaBarra)
          .map((b) => b.color)
          .toList();
      final coloresPunto = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle)
          .map((d) => d.color)
          .toList();

      expect(coloresPunto.length, 3);
      expect(coloresPunto, coloresTramo);
    });
  });
}
