import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/theme/app_theme.dart';
import 'package:misbolos/models/invoice.dart';
import 'package:misbolos/widgets/common/deslizar_para_cobrar.dart';

Invoice _factura(InvoiceStatus status) => Invoice(
  id: 'factura-1',
  numero: 7,
  fecha: DateTime(2026, 3, 20),
  clientId: 'cliente-1',
  gigId: 'bolo-1',
  items: const [],
  subtotal: 450,
  status: status,
);

Future<int> _montarYDeslizar(
  WidgetTester tester,
  InvoiceStatus status, {
  required double dx,
}) async {
  var cobros = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: DeslizarParaCobrar(
          invoice: _factura(status),
          alCobrar: () => cobros++,
          child: const SizedBox(height: 80, width: 400, child: Text('factura')),
        ),
      ),
    ),
  );
  await tester.fling(find.text('factura'), Offset(dx, 0), 1000);
  await tester.pumpAndSettle();
  return cobros;
}

void main() {
  testWidgets('una pendiente de cobro se cobra al deslizar a la derecha', (
    tester,
  ) async {
    expect(await _montarYDeslizar(tester, InvoiceStatus.enviada, dx: 400), 1);
  });

  testWidgets('una cobrada no se vuelve a cobrar', (tester) async {
    expect(await _montarYDeslizar(tester, InvoiceStatus.pagada, dx: 400), 0);
  });

  testWidgets('un borrador no se cobra deslizando', (tester) async {
    expect(await _montarYDeslizar(tester, InvoiceStatus.borrador, dx: 400), 0);
  });

  testWidgets('deslizar a la izquierda no cobra nada', (tester) async {
    expect(await _montarYDeslizar(tester, InvoiceStatus.enviada, dx: -400), 0);
  });

  test('solo las pendientes de cobro se pueden cobrar', () {
    expect(
      DeslizarParaCobrar.sePuedeCobrar(_factura(InvoiceStatus.enviada)),
      isTrue,
    );
    expect(
      DeslizarParaCobrar.sePuedeCobrar(_factura(InvoiceStatus.borrador)),
      isFalse,
    );
    expect(
      DeslizarParaCobrar.sePuedeCobrar(_factura(InvoiceStatus.pagada)),
      isFalse,
    );
  });
}
