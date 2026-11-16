import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/widgets/common/borrado_con_deshacer.dart';

/// Una pantalla de mentira con una lista y el borrado diferido, montada igual
/// que las de verdad: oculta al momento, borra al cerrarse el aviso y, al
/// salir de la pantalla, ejecuta lo que quedara en espera.
class _Pantalla extends StatefulWidget {
  final void Function(String) alBorrar;

  const _Pantalla({required this.alBorrar});

  @override
  State<_Pantalla> createState() => _PantallaState();
}

class _PantallaState extends State<_Pantalla> {
  final _elementos = ['uno', 'dos'];

  late final BorradoConDeshacer<String> _borrado = BorradoConDeshacer(
    alConfirmar: (elemento) async {
      // Como el provider de verdad: al borrar, el elemento sale de la lista.
      _elementos.remove(elemento);
      widget.alBorrar(elemento);
    },
    alCambiar: () {
      if (mounted) setState(() {});
    },
  );

  @override
  void dispose() {
    _borrado.confirmarPendientes();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _borrado.visibles(_elementos, (e) => e);
    return Scaffold(
      body: Column(
        children: [
          for (final elemento in visibles)
            TextButton(
              onPressed: () => _borrado.borrar(
                context: context,
                clave: elemento,
                elemento: elemento,
                mensaje: 'Borrado $elemento',
              ),
              child: Text(elemento),
            ),
        ],
      ),
    );
  }
}

void main() {
  /// Monta la pantalla y desliza el primer elemento.
  Future<List<String>> borrarUno(WidgetTester tester) async {
    final borrados = <String>[];
    await tester.pumpWidget(
      MaterialApp(home: _Pantalla(alBorrar: borrados.add)),
    );
    await tester.tap(find.text('uno'));
    // Un fotograma para que se oculte y otro para que el aviso acabe de entrar.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    return borrados;
  }

  testWidgets('deshacer no borra nada y devuelve el elemento a la lista', (
    tester,
  ) async {
    final borrados = await borrarUno(tester);

    // Desaparece al momento y el aviso ofrece deshacer.
    expect(find.text('uno'), findsNothing);
    expect(find.text('Borrado uno'), findsOneWidget);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();

    expect(borrados, isEmpty);
    expect(find.text('uno'), findsOneWidget);
  });

  testWidgets('dejar pasar el aviso borra de verdad', (tester) async {
    final borrados = await borrarUno(tester);

    // El aviso se cierra solo: nadie ha deshecho nada.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(borrados, ['uno']);
    expect(find.text('uno'), findsNothing);
  });

  testWidgets('salir de la pantalla ejecuta el borrado en espera', (
    tester,
  ) async {
    final borrados = await borrarUno(tester);
    expect(borrados, isEmpty);

    // Con el aviso aún abierto, se cierra la pantalla.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();

    expect(borrados, ['uno']);
  });
}
