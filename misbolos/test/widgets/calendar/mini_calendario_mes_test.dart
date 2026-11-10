import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/theme/app_theme.dart';
import 'package:misbolos/widgets/calendar/mini_calendario_mes.dart';

Widget _app({
  int year = 2026,
  int month = 10,
  Set<DateTime> marcados = const {},
  Set<DateTime> ocupados = const {},
  required DateTime hoy,
  required void Function(DateTime) onTocar,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SizedBox(
        width: 360,
        child: MiniCalendarioMes(
          year: year,
          month: month,
          marcados: marcados,
          ocupados: ocupados,
          hoy: hoy,
          onTocarDia: onTocar,
        ),
      ),
    ),
  );
}

void main() {
  final hoy = DateTime(2026, 10, 1);

  testWidgets('pinta los días del mes y las iniciales de la semana', (
    tester,
  ) async {
    await tester.pumpWidget(_app(hoy: hoy, onTocar: (_) {}));
    await tester.pumpAndSettle();

    for (final inicial in ['L', 'M', 'X', 'J', 'V', 'S', 'D']) {
      expect(find.text(inicial), findsWidgets);
    }
    // Octubre de 2026 tiene 31 días.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('32'), findsNothing);
  });

  testWidgets('febrero de un año no bisiesto acaba en 28', (tester) async {
    await tester.pumpWidget(
      _app(month: 2, hoy: DateTime(2026, 2, 1), onTocar: (_) {}),
    );
    await tester.pumpAndSettle();
    expect(find.text('28'), findsOneWidget);
    expect(find.text('29'), findsNothing);
  });

  testWidgets('tocar un día devuelve su clave normalizada', (tester) async {
    DateTime? tocado;
    await tester.pumpWidget(_app(hoy: hoy, onTocar: (f) => tocado = f));
    await tester.pumpAndSettle();

    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();
    expect(tocado, DateTime.utc(2026, 10, 9));
  });

  testWidgets('un día pasado no responde al toque', (tester) async {
    DateTime? tocado;
    await tester.pumpWidget(
      _app(hoy: DateTime(2026, 10, 15), onTocar: (f) => tocado = f),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('9'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tocado, isNull);

    await tester.tap(find.text('16'));
    await tester.pumpAndSettle();
    expect(tocado, DateTime.utc(2026, 10, 16));
  });

  testWidgets('los días ocupados llevan un punto', (tester) async {
    await tester.pumpWidget(
      _app(
        hoy: hoy,
        ocupados: {DateTime.utc(2026, 10, 9)},
        onTocar: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    final puntos = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.shape == BoxShape.circle);
    expect(puntos.length, 1);
  });
}
