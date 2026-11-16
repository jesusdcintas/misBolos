import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/services/hapticos.dart';
import 'package:misbolos/widgets/common/deslizar_horizontal.dart';

Widget _app({VoidCallback? onAnterior, VoidCallback? onSiguiente}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: DeslizarHorizontal(
          onAnterior: onAnterior,
          onSiguiente: onSiguiente,
          child: Container(
            width: 300,
            height: 200,
            color: Colors.grey,
            alignment: Alignment.center,
            child: const Text('contenido'),
          ),
        ),
      ),
    ),
  );
}

/// Un deslizamiento con velocidad suficiente.
Future<void> _deslizar(WidgetTester tester, double dx) async {
  await tester.fling(find.text('contenido'), Offset(dx, 0), 900);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => Hapticos.fijarActivadosEnTests(false));

  testWidgets('deslizar a la derecha va al anterior', (tester) async {
    var anteriores = 0;
    await tester.pumpWidget(_app(onAnterior: () => anteriores++));
    await _deslizar(tester, 300);
    expect(anteriores, 1);
  });

  testWidgets('deslizar a la izquierda va al siguiente', (tester) async {
    var siguientes = 0;
    await tester.pumpWidget(_app(onSiguiente: () => siguientes++));
    await _deslizar(tester, -300);
    expect(siguientes, 1);
  });

  group('límites', () {
    testWidgets('sin anterior, deslizar a la derecha no hace nada', (
      tester,
    ) async {
      var siguientes = 0;
      await tester.pumpWidget(
        _app(onAnterior: null, onSiguiente: () => siguientes++),
      );
      await _deslizar(tester, 300);
      expect(siguientes, 0, reason: 'tampoco debe disparar el otro lado');
    });

    testWidgets('sin siguiente, deslizar a la izquierda no hace nada', (
      tester,
    ) async {
      // Es el caso de Inicio en el periodo actual y el de Fechas libres en
      // el mes actual.
      var anteriores = 0;
      await tester.pumpWidget(
        _app(onAnterior: () => anteriores++, onSiguiente: null),
      );
      await _deslizar(tester, -300);
      expect(anteriores, 0);
    });

    testWidgets('sin ninguno de los dos, no pasa nada', (tester) async {
      await tester.pumpWidget(_app());
      await _deslizar(tester, 300);
      await _deslizar(tester, -300);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('un roce lento no cuenta', (tester) async {
    var anteriores = 0;
    await tester.pumpWidget(_app(onAnterior: () => anteriores++));

    final centro = tester.getCenter(find.text('contenido'));
    final gesto = await tester.startGesture(centro);
    for (var i = 0; i < 10; i++) {
      await gesto.moveBy(const Offset(6, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await gesto.up();
    await tester.pumpAndSettle();

    expect(anteriores, 0, reason: 'por debajo de la velocidad mínima');
  });

  testWidgets('el deslizamiento vertical no dispara nada', (tester) async {
    var anteriores = 0;
    var siguientes = 0;
    await tester.pumpWidget(
      _app(onAnterior: () => anteriores++, onSiguiente: () => siguientes++),
    );

    await tester.fling(find.text('contenido'), const Offset(0, -300), 900);
    await tester.pumpAndSettle();

    expect(anteriores, 0);
    expect(siguientes, 0);
  });
}
