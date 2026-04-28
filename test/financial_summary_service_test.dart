import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/models/asset.dart';
import 'package:misbolos/models/expense.dart';
import 'package:misbolos/models/gig.dart';
import 'package:misbolos/models/invoice.dart';
import 'package:misbolos/services/financial_summary_service.dart';

void main() {
  group('FinancialSummaryService', () {
    const service = FinancialSummaryService();

    test(
      'calcula IVA, deducciones, amortizacion y beneficio por trimestre',
      () {
        final invoice = Invoice(
          id: 'inv-1',
          numero: 1,
          fecha: DateTime(2026, 2, 10),
          clientId: 'client-1',
          gigId: 'gig-1',
          items: [
            InvoiceLineItem(
              cantidad: 1,
              descripcion: 'Bolo',
              precioUnitario: 1000,
            ),
          ],
          subtotal: 1000,
          ivaRate: 0.21,
          ivaAmount: 210,
          total: 1210,
          status: InvoiceStatus.pagada,
        );
        final pendingInvoice = invoice.copyWith(status: InvoiceStatus.enviada);
        final expense = Expense(
          fecha: DateTime(2026, 3, 1),
          concepto: 'Software',
          importeBase: 100,
          ivaAmount: 21,
          total: 121,
          porcentajeDeduccion: 50,
        );
        final asset = Asset(
          descripcion: 'Controladora',
          fechaCompra: DateTime(2026, 1, 15),
          importeTotal: 1200,
          importeConIva: 1452,
          ivaRate: 21,
          ivaAmount: 252,
          vidaUtilAnos: 4,
          createdAt: DateTime(2026, 1, 15),
        );

        final summary = service.calculate(
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 3, 31, 23, 59, 59),
          invoices: [invoice, pendingInvoice],
          expenses: [expense],
          assets: [asset],
          gigs: const [],
        );

        expect(summary.ingresosOficiales, 1000);
        expect(summary.ivaRepercutido, 210);
        expect(summary.gastosDeducibles, 50);
        expect(summary.ivaSoportadoGastos, 10.5);
        expect(summary.ivaSoportadoInversiones, 252);
        expect(summary.ivaAPagar, -52.5);
        expect(summary.amortizacion, 75);
        expect(summary.beneficioEstimado, 875);
      },
    );

    test('estima base e IVA de bolos historicos facturables sin factura', () {
      final summary = service.calculate(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 3, 31, 23, 59, 59),
        invoices: const [],
        expenses: const [],
        assets: const [],
        gigs: [
          Gig(
            id: 'gig-1',
            fecha: DateTime(2026, 2, 1),
            clientId: 'client-1',
            cachet: 1210,
            facturable: true,
            status: GigStatus.pagado,
          ),
        ],
      );

      expect(summary.ingresosHistoricosEstimados, closeTo(1000, 0.001));
      expect(summary.ivaRepercutidoHistoricoEstimado, closeTo(210, 0.001));
      expect(summary.hasEstimatedHistoricalData, isTrue);
    });
  });
}
