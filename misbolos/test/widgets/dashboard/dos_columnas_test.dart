import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/theme/app_theme.dart';
import 'package:misbolos/models/financial_summary.dart';
import 'package:misbolos/providers/stats_provider.dart';
import 'package:misbolos/widgets/dashboard/income_period_card.dart';
import 'package:misbolos/widgets/dashboard/taxes_period_card.dart';

const _periodo = DashboardPeriod(
  mode: DashboardPeriodMode.anio,
  year: 2026,
  month: 10,
  quarter: 4,
);

/// Las dos tarjetas en fila, como las monta Inicio a partir de 700 px.
Widget _par({required bool igualarAltura}) {
  final fila = Row(
    crossAxisAlignment: igualarAltura
        ? CrossAxisAlignment.stretch
        : CrossAxisAlignment.start,
    children: [
      Expanded(
        child: IncomePeriodCard(
          stats: PeriodDashboardStats(
            cobradoFacturas: 10128,
            pendiente: 4997.40,
            previsto: 800,
            totalBolos: 12,
          ),
          period: _periodo,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: TaxesPeriodCard(
          summary: FinancialSummary(
            from: DateTime(2026, 1, 1),
            to: DateTime(2026, 12, 31),
            ingresosOficiales: 15125.40,
            ivaRepercutidoBruto: 3176.33,
            irpfTeorico: 3025.08,
            irpfRetenido: 2268.81,
            irpfAIngresar: 756.27,
          ),
          period: _periodo,
        ),
      ),
    ],
  );

  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SizedBox(
        width: 900,
        child: SingleChildScrollView(
          child: igualarAltura ? IntrinsicHeight(child: fila) : fila,
        ),
      ),
    ),
  );
}

double _alto(WidgetTester tester, Type tipo) =>
    tester.getSize(find.byType(tipo)).height;

void main() {
  testWidgets('sin igualar, las dos tarjetas tienen alturas distintas', (
    tester,
  ) async {
    await tester.pumpWidget(_par(igualarAltura: false));
    await tester.pumpAndSettle();

    expect(
      _alto(tester, IncomePeriodCard),
      isNot(closeTo(_alto(tester, TaxesPeriodCard), 0.5)),
      reason: 'si ya fueran iguales, el test no probaría nada',
    );
  });

  testWidgets('igualando, las dos tarjetas miden lo mismo', (tester) async {
    await tester.pumpWidget(_par(igualarAltura: true));
    await tester.pumpAndSettle();

    final ingresos = _alto(tester, IncomePeriodCard);
    final impuestos = _alto(tester, TaxesPeriodCard);
    expect(ingresos, closeTo(impuestos, 0.5));
    expect(ingresos, greaterThan(0));
  });

  testWidgets('no hay excepciones de layout al medir el alto intrínseco', (
    tester,
  ) async {
    await tester.pumpWidget(_par(igualarAltura: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
