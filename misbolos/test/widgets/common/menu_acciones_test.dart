import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/utils/date_formatter.dart';
import 'package:misbolos/models/franja_bolo.dart';
import 'package:misbolos/models/gig.dart';
import 'package:misbolos/models/invoice.dart';
import 'package:misbolos/widgets/common/acciones_bolo.dart';
import 'package:misbolos/widgets/common/menu_acciones.dart';

Gig _bolo({
  bool facturable = true,
  GigStatus status = GigStatus.confirmado,
  String? invoiceId,
}) {
  return Gig(
    id: 'bolo-1',
    fecha: DateTime(2026, 3, 14),
    clientId: 'cliente-1',
    cachet: 450,
    facturable: facturable,
    status: status,
    franja: FranjaBolo.noche,
    invoiceId: invoiceId,
  );
}

Invoice _factura(InvoiceStatus status) {
  return Invoice(
    numero: 7,
    fecha: DateTime(2026, 3, 20),
    clientId: 'cliente-1',
    gigId: 'bolo-1',
    items: const [],
    subtotal: 450,
    status: status,
  );
}

void main() {
  group('acciones de un bolo', () {
    test('uno facturable y sin factura puede facturarse y cancelarse', () {
      expect(accionesDeBolo(_bolo()), [
        AccionBolo.ver,
        AccionBolo.editar,
        AccionBolo.duplicar,
        AccionBolo.facturar,
        AccionBolo.cancelar,
      ]);
    });

    test('con factura se ofrece verla, no volver a facturar', () {
      final acciones = accionesDeBolo(_bolo(invoiceId: 'factura-1'));
      expect(acciones, contains(AccionBolo.verFactura));
      expect(acciones, isNot(contains(AccionBolo.facturar)));
    });

    test('uno no facturable no se factura', () {
      expect(
        accionesDeBolo(_bolo(facturable: false)),
        isNot(contains(AccionBolo.facturar)),
      );
    });

    test('uno cancelado no se cancela otra vez ni se factura', () {
      final acciones = accionesDeBolo(_bolo(status: GigStatus.cancelado));
      expect(acciones, isNot(contains(AccionBolo.cancelar)));
      expect(acciones, isNot(contains(AccionBolo.facturar)));
      expect(acciones, contains(AccionBolo.duplicar));
    });
  });

  group('acciones de una factura', () {
    test('una pendiente de cobro se puede marcar como cobrada', () {
      expect(
        accionesDeFactura(
          _factura(InvoiceStatus.enviada),
          puedeEnviarEmail: true,
        ),
        [
          AccionFactura.ver,
          AccionFactura.compartirPdf,
          AccionFactura.enviarEmail,
          AccionFactura.marcarCobrada,
        ],
      );
    });

    test('una cobrada ya no se vuelve a cobrar', () {
      expect(
        accionesDeFactura(
          _factura(InvoiceStatus.pagada),
          puedeEnviarEmail: false,
        ),
        [AccionFactura.ver, AccionFactura.compartirPdf],
      );
    });

    test('sin email del cliente no se ofrece enviarlo', () {
      expect(
        accionesDeFactura(
          _factura(InvoiceStatus.borrador),
          puedeEnviarEmail: false,
        ),
        isNot(contains(AccionFactura.enviarEmail)),
      );
    });
  });

  group('duplicar un bolo', () {
    test('copia cliente, caché, franja y facturable con la fecha de hoy', () {
      final ruta = Uri.parse(
        rutaDuplicarBolo(
          _bolo(invoiceId: 'factura-1', status: GigStatus.cobrado),
        ),
      );

      expect(ruta.path, '/gig/new');
      expect(
        ruta.queryParameters['fecha'],
        DateFormatter.isoDay(DateTime.now()),
      );
      expect(ruta.queryParameters['cliente'], 'cliente-1');
      expect(ruta.queryParameters['cachet'], '450.0');
      expect(ruta.queryParameters['franja'], FranjaBolo.noche.dbValue);
      expect(ruta.queryParameters['facturable'], '1');
    });

    test('no arrastra la factura ni el estado del bolo original', () {
      final ruta = Uri.parse(
        rutaDuplicarBolo(
          _bolo(invoiceId: 'factura-1', status: GigStatus.cobrado),
        ),
      );
      final claves = ruta.queryParameters.keys;

      expect(claves, isNot(contains('invoiceId')));
      expect(claves, isNot(contains('estado')));
      expect(claves, isNot(contains('status')));
    });

    test('uno no facturable se duplica como no facturable', () {
      final ruta = Uri.parse(rutaDuplicarBolo(_bolo(facturable: false)));
      expect(ruta.queryParameters['facturable'], '0');
    });
  });
}
