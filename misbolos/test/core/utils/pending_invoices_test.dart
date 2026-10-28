import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/utils/pending_invoices.dart';
import 'package:misbolos/models/invoice.dart';

Invoice _factura({
  required String id,
  required DateTime fecha,
  required double total,
  InvoiceStatus status = InvoiceStatus.enviada,
}) {
  return Invoice(
    id: id,
    gigId: 'gig-$id',
    clientId: 'cliente-$id',
    numero: 1,
    fecha: fecha,
    items: const [],
    subtotal: total,
    ivaRate: 0,
    ivaAmount: 0,
    total: total,
    status: status,
  );
}

void main() {
  final hoy = DateTime(2026, 10, 28);

  group('facturasPendientesDeCobro', () {
    test('una factura de hoy aparece', () {
      final f = _factura(id: 'a', fecha: hoy, total: 500);
      expect(facturasPendientesDeCobro([f], hoy: hoy), [f]);
      expect(diasDesdeEmision(f.fecha, hoy: hoy), 0);
    });

    test('una factura con fecha futura no aparece', () {
      final futura = _factura(
        id: 'b',
        fecha: DateTime(2026, 10, 30),
        total: 800,
      );
      expect(facturasPendientesDeCobro([futura], hoy: hoy), isEmpty);
    });

    test('solo entran las enviadas: ni borradores ni pagadas', () {
      final borrador = _factura(
        id: 'c',
        fecha: DateTime(2026, 10, 1),
        total: 100,
        status: InvoiceStatus.borrador,
      );
      final pagada = _factura(
        id: 'd',
        fecha: DateTime(2026, 10, 2),
        total: 200,
        status: InvoiceStatus.pagada,
      );
      final enviada = _factura(id: 'e', fecha: DateTime(2026, 10, 3), total: 300);

      final resultado = facturasPendientesDeCobro(
        [borrador, pagada, enviada],
        hoy: hoy,
      );
      expect(resultado.map((i) => i.id), ['e']);
    });

    test('se ordenan de más antigua a más nueva', () {
      final nueva = _factura(id: 'n', fecha: DateTime(2026, 10, 20), total: 100);
      final vieja = _factura(id: 'v', fecha: DateTime(2026, 9, 1), total: 200);
      final media = _factura(id: 'm', fecha: DateTime(2026, 10, 5), total: 300);

      final resultado = facturasPendientesDeCobro(
        [nueva, vieja, media],
        hoy: hoy,
      );
      expect(resultado.map((i) => i.id), ['v', 'm', 'n']);
    });

    test('una lista vacía da una lista vacía', () {
      expect(facturasPendientesDeCobro(const [], hoy: hoy), isEmpty);
    });

    test('la hora de emisión no excluye una factura de hoy', () {
      final f = _factura(
        id: 'f',
        fecha: DateTime(2026, 10, 28, 23, 30),
        total: 400,
      );
      expect(facturasPendientesDeCobro([f], hoy: hoy), [f]);
    });
  });

  group('totalPendienteDeCobro', () {
    test('suma todas las facturas que recibe, no solo las visibles', () {
      final facturas = [
        _factura(id: '1', fecha: DateTime(2026, 9, 1), total: 1000),
        _factura(id: '2', fecha: DateTime(2026, 9, 10), total: 2000),
        _factura(id: '3', fecha: DateTime(2026, 9, 20), total: 500.40),
        _factura(id: '4', fecha: DateTime(2026, 10, 1), total: 45),
      ];
      final pendientes = facturasPendientesDeCobro(facturas, hoy: hoy);
      expect(pendientes.length, 4);
      expect(totalPendienteDeCobro(pendientes), closeTo(3545.40, 0.001));
      // El total no es el de las tres primeras.
      expect(
        totalPendienteDeCobro(pendientes.take(3).toList()),
        closeTo(3500.40, 0.001),
      );
    });

    test('una lista vacía suma 0', () {
      expect(totalPendienteDeCobro(const []), 0);
    });
  });

  group('diasDesdeEmision', () {
    test('cuenta los días transcurridos', () {
      expect(diasDesdeEmision(DateTime(2026, 10, 9), hoy: hoy), 19);
    });

    test('nunca es negativo con una fecha futura', () {
      expect(diasDesdeEmision(DateTime(2026, 10, 30), hoy: hoy), 0);
    });

    test('no se come un día al cruzar el cambio de hora', () {
      // Del 15 de febrero al 20 de abril de 2026 hay 64 días; el cambio de
      // hora de marzo deja un día de 23 horas.
      expect(
        diasDesdeEmision(DateTime(2026, 2, 15), hoy: DateTime(2026, 4, 20)),
        64,
      );
    });
  });
}
