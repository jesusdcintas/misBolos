import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/theme/app_theme.dart';
import 'package:misbolos/core/utils/confirmar_descartar.dart';

/// Una pantalla que se abre encima y se puede cerrar con la flecha.
Widget _app({required bool hayCambios}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FormularioConCambios(
                  hayCambios: hayCambios,
                  child: const Scaffold(
                    body: Center(child: Text('Formulario')),
                  ),
                ),
              ),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _abrirFormulario(WidgetTester tester) async {
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  expect(find.text('Formulario'), findsOneWidget);
}

void main() {
  testWidgets('sin cambios, sale sin preguntar', (tester) async {
    await tester.pumpWidget(_app(hayCambios: false));
    await _abrirFormulario(tester);

    final navegador = tester.state<NavigatorState>(find.byType(Navigator));
    navegador.maybePop();
    await tester.pumpAndSettle();

    expect(find.text('¿Descartar los cambios?'), findsNothing);
    expect(find.text('Formulario'), findsNothing);
  });

  testWidgets('con cambios, pregunta antes de salir', (tester) async {
    await tester.pumpWidget(_app(hayCambios: true));
    await _abrirFormulario(tester);

    tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();

    expect(find.text('¿Descartar los cambios?'), findsOneWidget);
    expect(find.text('Descartar'), findsOneWidget);
    expect(find.text('Seguir editando'), findsOneWidget);
    // Sigue en el formulario mientras no responda.
    expect(find.text('Formulario'), findsOneWidget);
  });

  testWidgets('«Seguir editando» se queda en el formulario', (tester) async {
    await tester.pumpWidget(_app(hayCambios: true));
    await _abrirFormulario(tester);

    tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();

    expect(find.text('Formulario'), findsOneWidget);
  });

  testWidgets('«Descartar» sale del formulario', (tester) async {
    await tester.pumpWidget(_app(hayCambios: true));
    await _abrirFormulario(tester);

    tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();

    expect(find.text('Formulario'), findsNothing);
    expect(find.text('Abrir'), findsOneWidget);
  });

  testWidgets('tras guardar, hayCambios en false deja salir sin preguntar', (
    tester,
  ) async {
    // Es lo que hacen los formularios al poner _guardado en true: aunque se
    // hubieran tocado campos, al guardar dejan de considerarse cambios.
    await tester.pumpWidget(_app(hayCambios: false));
    await _abrirFormulario(tester);

    tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();

    expect(find.text('¿Descartar los cambios?'), findsNothing);
    expect(find.text('Formulario'), findsNothing);
  });
}
