import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/services/guia_inicio.dart';
import 'package:misbolos/core/services/hapticos.dart';
import 'package:misbolos/core/theme/app_theme.dart';
import 'package:misbolos/widgets/tutorial/cierre_guia.dart';
import 'package:misbolos/widgets/tutorial/tarjeta_guia_inicio.dart';

List<EstadoPasoGuia> _pasos({
  int hechos = 0,
  Set<PasoGuia> saltados = const {},
}) {
  final valores = PasoGuia.values;
  return [
    for (final (indice, paso) in valores.indexed)
      EstadoPasoGuia(
        paso,
        hecho: indice < hechos,
        saltado: saltados.contains(paso),
      ),
  ];
}

Future<void> _montar(
  WidgetTester tester, {
  required List<EstadoPasoGuia> pasos,
  ThemeData? tema,
  void Function(PasoGuia)? alHacerlo,
  void Function(PasoGuia)? alSaltar,
  VoidCallback? alOcultar,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: tema ?? AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: TarjetaGuiaInicio(
            pasos: pasos,
            siguiente: siguientePaso(pasos),
            alHacerlo: alHacerlo ?? (_) {},
            alSaltar: alSaltar ?? (_) {},
            alOcultar: alOcultar ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => Hapticos.fijarActivadosEnTests(false));

  testWidgets('enseña el progreso y los doce pasos', (tester) async {
    await _montar(tester, pasos: _pasos(hechos: 3));

    expect(find.text('Guía de inicio'), findsOneWidget);
    expect(find.text('3 de 12'), findsOneWidget);
    for (final paso in PasoGuia.values) {
      expect(find.text(paso.titulo), findsOneWidget, reason: paso.name);
    }
  });

  testWidgets('solo el paso que toca trae sus botones', (tester) async {
    await _montar(tester, pasos: _pasos(hechos: 3));

    // El siguiente es el cuarto: datos de facturación.
    expect(find.text('Hacerlo ahora'), findsOneWidget);
    expect(find.text('Saltar este paso'), findsOneWidget);
    expect(find.text(PasoGuia.datosFacturacion.detalle), findsOneWidget);
  });

  testWidgets('«Hacerlo ahora» avisa de qué paso se trata', (tester) async {
    final pedidos = <PasoGuia>[];
    await _montar(tester, pasos: _pasos(hechos: 3), alHacerlo: pedidos.add);

    await tester.tap(find.text('Hacerlo ahora'));
    await tester.pump();

    expect(pedidos, [PasoGuia.datosFacturacion]);
  });

  testWidgets('«Saltar este paso» se puede pedir', (tester) async {
    final saltados = <PasoGuia>[];
    await _montar(tester, pasos: _pasos(), alSaltar: saltados.add);

    await tester.tap(find.text('Saltar este paso'));
    await tester.pump();

    expect(saltados, [PasoGuia.google]);
  });

  testWidgets('un paso saltado se tacha y deja pasar al siguiente', (
    tester,
  ) async {
    await _montar(tester, pasos: _pasos(saltados: {PasoGuia.google}));

    expect(find.text('1 de 12'), findsOneWidget);
    expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    expect(find.text(PasoGuia.carpetas.detalle), findsOneWidget);
  });

  testWidgets('la guía se puede ocultar', (tester) async {
    var ocultada = 0;
    await _montar(tester, pasos: _pasos(), alOcultar: () => ocultada++);

    await tester.tap(find.text('Ocultar la guía'));
    await tester.pump();

    expect(ocultada, 1);
  });

  for (final (nombre, tema) in [
    ('claro', AppTheme.light),
    ('oscuro', AppTheme.dark),
  ]) {
    testWidgets('se lee en modo $nombre', (tester) async {
      await _montar(tester, pasos: _pasos(hechos: 2), tema: tema);

      expect(find.text('2 de 12'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    });
  }

  group('el cierre', () {
    testWidgets('cuenta lo de la factura de prueba y los tres sitios', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(child: CierreGuia(alOcultar: () {})),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('factura de prueba'), findsOneWidget);
      expect(find.textContaining('impuestos estimados'), findsOneWidget);
      expect(find.textContaining('Fechas libres'), findsOneWidget);
      expect(find.textContaining('«?»'), findsOneWidget);
    });
  });
}
