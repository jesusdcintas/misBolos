import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/services/hapticos.dart';
import 'package:misbolos/core/theme/app_theme.dart';
import 'package:misbolos/core/theme/app_theme_colors.dart';
import 'package:misbolos/core/utils/primeros_pasos.dart';
import 'package:misbolos/widgets/dashboard/tarjeta_primeros_pasos.dart';

List<EstadoPasoInicial> _pasos({int hechos = 0}) => [
  for (final (indice, paso) in PasoInicial.values.indexed)
    EstadoPasoInicial(paso, completado: indice < hechos),
];

Future<void> _montar(
  WidgetTester tester, {
  required ThemeData tema,
  int hechos = 0,
  ValueChanged<PasoInicial>? alTocarPaso,
  VoidCallback? alOcultar,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: tema,
      home: Scaffold(
        body: TarjetaPrimerosPasos(
          pasos: _pasos(hechos: hechos),
          alTocarPaso: alTocarPaso ?? (_) {},
          alOcultar: alOcultar ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => Hapticos.fijarActivadosEnTests(false));

  testWidgets('enseña los cinco pasos y cuántos llevas', (tester) async {
    await _montar(tester, tema: AppTheme.light, hechos: 2);

    expect(find.text('Primeros pasos'), findsOneWidget);
    expect(find.text('2 de 5'), findsOneWidget);
    for (final paso in PasoInicial.values) {
      expect(find.text(paso.titulo), findsOneWidget, reason: paso.name);
    }
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
  });

  testWidgets('con todo hecho desaparece sola', (tester) async {
    await _montar(tester, tema: AppTheme.light, hechos: 5);

    expect(find.text('Primeros pasos'), findsNothing);
  });

  testWidgets('tocar un paso pendiente lleva a su pantalla', (tester) async {
    final tocados = <PasoInicial>[];
    await _montar(tester, tema: AppTheme.light, alTocarPaso: tocados.add);

    await tester.tap(find.text(PasoInicial.cliente.titulo));
    await tester.pump();

    expect(tocados, [PasoInicial.cliente]);
  });

  testWidgets('un paso hecho ya no lleva a ningún sitio', (tester) async {
    final tocados = <PasoInicial>[];
    await _montar(
      tester,
      tema: AppTheme.light,
      hechos: 1,
      alTocarPaso: tocados.add,
    );

    await tester.tap(find.text(PasoInicial.datosFiscales.titulo));
    await tester.pump();

    expect(tocados, isEmpty);
  });

  testWidgets('se puede ocultar', (tester) async {
    var ocultada = 0;
    await _montar(tester, tema: AppTheme.light, alOcultar: () => ocultada++);

    await tester.tap(find.text('Ocultar'));
    await tester.pump();

    expect(ocultada, 1);
  });

  for (final (nombre, tema) in [
    ('claro', AppTheme.light),
    ('oscuro', AppTheme.dark),
  ]) {
    testWidgets('se lee en modo $nombre', (tester) async {
      await _montar(tester, tema: tema, hechos: 1);

      // El texto sale del tema, así que contrasta con su propio fondo.
      final contexto = tester.element(find.text('Primeros pasos'));
      final colores = contexto.colors;
      final titulo = tester.widget<Text>(find.text('Primeros pasos'));

      expect(titulo.style?.color, colores.textPrimary);
      expect(find.text('1 de 5'), findsOneWidget);
    });
  }
}
