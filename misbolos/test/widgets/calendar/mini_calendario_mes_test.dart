import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:misbolos/core/theme/app_theme.dart';
import 'package:misbolos/widgets/calendar/mini_calendario_mes.dart';

Widget _app({
  int year = 2026,
  int month = 10,
  Set<DateTime> marcados = const {},
  Map<DateTime, String> bolosPorDia = const {},
  double altoCelda = 52,
  required DateTime hoy,
  required void Function(DateTime) onTocar,
  bool oscuro = false,
}) {
  return MaterialApp(
    theme: oscuro ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      body: SizedBox(
        width: 520,
        child: MiniCalendarioMes(
          year: year,
          month: month,
          marcados: marcados,
          bolosPorDia: bolosPorDia,
          altoCelda: altoCelda,
          hoy: hoy,
          onTocarDia: onTocar,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_ES', null);
  });

  final hoy = DateTime(2026, 10, 1);

  testWidgets('pinta los días del mes', (tester) async {
    await tester.pumpWidget(_app(hoy: hoy, onTocar: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('32'), findsNothing);
  });

  testWidgets('la cabecera de la semana sale una sola vez y en es', (
    tester,
  ) async {
    await tester.pumpWidget(_app(hoy: hoy, onTocar: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('lun'), findsOneWidget);
    expect(find.text('mié'), findsOneWidget);
    expect(find.text('sáb'), findsOneWidget);
    expect(find.text('dom'), findsOneWidget);
    // Ya no está la fila de iniciales repetida.
    expect(find.text('L'), findsNothing);
    expect(find.text('X'), findsNothing);
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

  group('estados de las celdas', () {
    testWidgets('un día con bolo lleva la etiqueta Bolo', (tester) async {
      await tester.pumpWidget(
        _app(
          hoy: hoy,
          bolosPorDia: {DateTime.utc(2026, 10, 9): 'Bahía Sur'},
          onTocar: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bolo'), findsOneWidget);
    });

    testWidgets('un día con bolo lleva tooltip con el cliente', (tester) async {
      await tester.pumpWidget(
        _app(
          hoy: hoy,
          bolosPorDia: {DateTime.utc(2026, 10, 9): 'Bahía Sur'},
          onTocar: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      final tooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(tooltips, contains('Bahía Sur'));
    });

    testWidgets('hoy lleva la etiqueta Hoy si no está marcado', (tester) async {
      await tester.pumpWidget(
        _app(hoy: DateTime(2026, 10, 15), onTocar: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hoy'), findsOneWidget);
    });

    testWidgets('hoy marcado no lleva la etiqueta Hoy', (tester) async {
      await tester.pumpWidget(
        _app(
          hoy: DateTime(2026, 10, 15),
          marcados: {DateTime.utc(2026, 10, 15)},
          onTocar: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hoy'), findsNothing);
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

    testWidgets('un día pasado con bolo se pinta como pasado', (tester) async {
      await tester.pumpWidget(
        _app(
          hoy: DateTime(2026, 10, 15),
          bolosPorDia: {DateTime.utc(2026, 10, 9): 'Bahía Sur'},
          onTocar: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      // El pasado manda: no se anuncia un bolo que ya no se puede mover.
      expect(find.text('Bolo'), findsNothing);
    });
  });

  group('altura de las celdas', () {
    testWidgets('en escritorio no pasan de 60 px', (tester) async {
      await tester.pumpWidget(_app(hoy: hoy, onTocar: (_) {}));
      await tester.pumpAndSettle();

      final alto = tester.getSize(find.ancestor(
        of: find.text('9'),
        matching: find.byType(InkWell),
      ).first).height;
      expect(alto, lessThanOrEqualTo(60));
      expect(alto, closeTo(52, 0.5));
    });

    testWidgets('en móvil son algo más bajas', (tester) async {
      await tester.pumpWidget(_app(hoy: hoy, altoCelda: 46, onTocar: (_) {}));
      await tester.pumpAndSettle();

      final alto = tester.getSize(find.ancestor(
        of: find.text('9'),
        matching: find.byType(InkWell),
      ).first).height;
      expect(alto, closeTo(46, 0.5));
    });

    testWidgets('las celdas no son cuadradas', (tester) async {
      await tester.pumpWidget(_app(hoy: hoy, onTocar: (_) {}));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.ancestor(
        of: find.text('9'),
        matching: find.byType(InkWell),
      ).first);
      expect(size.width, isNot(closeTo(size.height, 2)));
    });
  });

  testWidgets('la leyenda nombra los tres estados', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: LeyendaMiniCalendario()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Libre'), findsOneWidget);
    expect(find.text('Con bolo'), findsOneWidget);
    expect(find.text('Pasado'), findsOneWidget);
  });

  testWidgets('también se pinta en modo oscuro', (tester) async {
    await tester.pumpWidget(
      _app(
        hoy: hoy,
        oscuro: true,
        bolosPorDia: {DateTime.utc(2026, 10, 9): 'Bahía Sur'},
        marcados: {DateTime.utc(2026, 10, 2)},
        onTocar: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Bolo'), findsOneWidget);
  });
}
