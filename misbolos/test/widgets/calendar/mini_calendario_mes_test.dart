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
  Map<DateTime, String> parciales = const {},
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
          parciales: parciales,
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

  group('alineación de los días con su columna', () {
    /// Centro horizontal de un texto.
    double x(WidgetTester tester, String texto) =>
        tester.getCenter(find.text(texto)).dx;

    /// Filas de celdas que dibuja la rejilla.
    int filas(WidgetTester tester, double alto) => tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((s) => s.height == alto)
        .length;

    testWidgets('noviembre de 2026: el 1 va bajo dom, no bajo lun', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(month: 11, hoy: DateTime(2026, 11, 1), onTocar: (_) {}),
      );
      await tester.pumpAndSettle();

      expect(x(tester, '1'), closeTo(x(tester, 'dom'), 1));
      expect(x(tester, '1'), isNot(closeTo(x(tester, 'lun'), 1)));
    });

    testWidgets('noviembre de 2026: el 13 bajo vie y el 10 bajo mar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(month: 11, hoy: DateTime(2026, 11, 1), onTocar: (_) {}),
      );
      await tester.pumpAndSettle();

      expect(x(tester, '13'), closeTo(x(tester, 'vie'), 1));
      expect(x(tester, '10'), closeTo(x(tester, 'mar'), 1));
    });

    testWidgets('noviembre de 2026: la primera fila no está vacía', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(month: 11, hoy: DateTime(2026, 11, 1), onTocar: (_) {}),
      );
      await tester.pumpAndSettle();

      // El 1 está en la primera fila de celdas, justo bajo la cabecera.
      final yCabecera = tester.getCenter(find.text('dom')).dy;
      final yUno = tester.getCenter(find.text('1')).dy;
      final yOcho = tester.getCenter(find.text('8')).dy;
      expect(yUno - yCabecera, lessThan(yOcho - yUno));
    });

    testWidgets('junio de 2026: el 1 va bajo lun', (tester) async {
      await tester.pumpWidget(
        _app(month: 6, hoy: DateTime(2026, 6, 1), onTocar: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(x(tester, '1'), closeTo(x(tester, 'lun'), 1));
    });

    testWidgets('abril de 2026: el 1 va bajo mié', (tester) async {
      await tester.pumpWidget(
        _app(month: 4, hoy: DateTime(2026, 4, 1), onTocar: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(x(tester, '1'), closeTo(x(tester, 'mié'), 1));
    });

    testWidgets('agosto de 2026: el 1 va bajo sáb', (tester) async {
      await tester.pumpWidget(
        _app(month: 8, hoy: DateTime(2026, 8, 1), onTocar: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(x(tester, '1'), closeTo(x(tester, 'sáb'), 1));
    });

    testWidgets('febrero de 2027: exactamente cuatro filas', (tester) async {
      await tester.pumpWidget(
        _app(year: 2027, month: 2, hoy: DateTime(2027, 2, 1), onTocar: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(filas(tester, 52), 4);
    });

    testWidgets('febrero de 2027: el 28 se dibuja', (tester) async {
      await tester.pumpWidget(
        _app(year: 2027, month: 2, hoy: DateTime(2027, 2, 1), onTocar: (_) {}),
      );
      await tester.pumpAndSettle();
      // Con el desfase anterior el 28 se salía de la rejilla.
      expect(find.text('28'), findsOneWidget);
      expect(x(tester, '28'), closeTo(x(tester, 'dom'), 1));
    });

    testWidgets('noviembre de 2026: tocar el 13 devuelve el 13', (
      tester,
    ) async {
      DateTime? tocado;
      await tester.pumpWidget(
        _app(
          month: 11,
          hoy: DateTime(2026, 11, 1),
          onTocar: (f) => tocado = f,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('13'));
      await tester.pumpAndSettle();
      expect(tocado, DateTime.utc(2026, 11, 13));
    });
  });

  group('días parcialmente libres', () {
    testWidgets('llevan la etiqueta de la franja que queda libre', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          hoy: hoy,
          parciales: {DateTime.utc(2026, 10, 9): 'Noche'},
          onTocar: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Noche'), findsOneWidget);
    });

    testWidgets('el parcial manda sobre el día con bolo', (tester) async {
      await tester.pumpWidget(
        _app(
          hoy: hoy,
          bolosPorDia: {DateTime.utc(2026, 10, 9): 'Bahía Sur · Tarde'},
          parciales: {DateTime.utc(2026, 10, 9): 'Noche'},
          onTocar: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      // Se ofrece la noche libre, no se anuncia como ocupado.
      expect(find.text('Noche'), findsOneWidget);
      expect(find.text('Bolo'), findsNothing);
    });

    testWidgets('un parcial con bolo conserva el tooltip', (tester) async {
      await tester.pumpWidget(
        _app(
          hoy: hoy,
          bolosPorDia: {DateTime.utc(2026, 10, 9): 'Bahía Sur · Tarde'},
          parciales: {DateTime.utc(2026, 10, 9): 'Noche'},
          onTocar: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      final mensajes = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(mensajes, contains('Bahía Sur · Tarde'));
    });

    testWidgets('un día pasado no se ofrece como parcial', (tester) async {
      await tester.pumpWidget(
        _app(
          hoy: DateTime(2026, 10, 15),
          parciales: {DateTime.utc(2026, 10, 9): 'Noche'},
          onTocar: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Noche'), findsNothing);
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
    expect(find.text('Media libre'), findsOneWidget);
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
