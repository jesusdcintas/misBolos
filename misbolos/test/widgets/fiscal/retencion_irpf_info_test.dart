import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/widgets/fiscal/retencion_irpf_info.dart';

/// Pantalla mínima con un botón que abre la ventana, para no depender de
/// Ajustes ni del formulario de factura (que sí necesitan Supabase).
Widget _appConBoton({Size? tamanoPantalla}) {
  Widget boton = Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: IconButton(
          icon: const Icon(Icons.info_outline),
          tooltip: '¿Qué retención me corresponde?',
          onPressed: () => mostrarRetencionIrpfInfo(context),
        ),
      ),
    ),
  );
  if (tamanoPantalla != null) {
    boton = MediaQuery(
      data: MediaQueryData(size: tamanoPantalla),
      child: boton,
    );
  }
  return MaterialApp(home: boton);
}

void _esperaElContenido() {
  expect(find.text('Retención IRPF en tus facturas'), findsOneWidget);
  expect(find.text('15%'), findsOneWidget);
  expect(find.text('7%'), findsOneWidget);
  expect(find.text('0%'), findsOneWidget);
  expect(find.textContaining('siempre del 20 %'), findsOneWidget);
  expect(find.text('Entendido'), findsOneWidget);
}

void main() {
  testWidgets('en pantalla ancha abre un diálogo con los tres porcentajes', (
    tester,
  ) async {
    await tester.pumpWidget(_appConBoton(tamanoPantalla: const Size(1200, 900)));
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    _esperaElContenido();
  });

  testWidgets('en móvil abre una hoja inferior con los tres porcentajes', (
    tester,
  ) async {
    await tester.pumpWidget(_appConBoton(tamanoPantalla: const Size(390, 844)));
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    _esperaElContenido();
  });

  testWidgets('muestra la explicación de cada porcentaje', (tester) async {
    await tester.pumpWidget(_appConBoton(tamanoPantalla: const Size(1200, 900)));
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.textContaining('salas, promotoras, agencias'), findsOneWidget);
    expect(find.textContaining('Nuevos autónomos'), findsOneWidget);
    expect(find.textContaining('particulares'), findsOneWidget);
  });

  testWidgets('el botón Entendido cierra la ventana', (tester) async {
    await tester.pumpWidget(_appConBoton(tamanoPantalla: const Size(390, 844)));
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('Entendido'), findsOneWidget);

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.text('Retención IRPF en tus facturas'), findsNothing);
  });

  group('RetencionIrpfAviso', () {
    testWidgets('sin rate solo muestra la nota del 20 %', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RetencionIrpfAviso())),
      );
      expect(find.textContaining('siempre del 20 %'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('con un rate válido muestra su explicación', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RetencionIrpfAviso(rate: 0.07)),
        ),
      );
      expect(find.textContaining('Nuevos autónomos'), findsOneWidget);
      expect(find.textContaining('siempre del 20 %'), findsOneWidget);
    });

    testWidgets('con un rate fuera de la lista avisa', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RetencionIrpfAviso(rate: 0.19)),
        ),
      );
      expect(find.textContaining('19% que ya no es una opción'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });
}
