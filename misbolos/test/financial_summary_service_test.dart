import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/services/drive_document_sync_service.dart';
import 'package:misbolos/models/asset.dart';
import 'package:misbolos/models/expense.dart';
import 'package:misbolos/models/invoice.dart';
import 'package:misbolos/services/financial_summary_service.dart';

Invoice _invoice({
  required String id,
  required int numero,
  required DateTime fecha,
  double subtotal = 1000,
  double ivaAmount = 210,
  double irpfRate = 0,
  double? irpfAmount,
  InvoiceStatus status = InvoiceStatus.pagada,
}) {
  return Invoice(
    id: id,
    numero: numero,
    fecha: fecha,
    clientId: 'client-1',
    gigId: 'gig-1',
    items: [
      InvoiceLineItem(cantidad: 1, descripcion: 'Bolo', precioUnitario: subtotal),
    ],
    subtotal: subtotal,
    ivaRate: 0.21,
    ivaAmount: ivaAmount,
    irpfRate: irpfRate,
    irpfAmount: irpfAmount,
    total: subtotal + ivaAmount - (irpfAmount ?? subtotal * irpfRate),
    status: status,
  );
}

void main() {
  group('FinancialSummaryService', () {
    const service = FinancialSummaryService();
    final from = DateTime(2026, 1, 1);
    final to = DateTime(2026, 3, 31, 23, 59, 59);

    test('IVA 21% sin IRPF: IVA bruto y IRPF teórico sin restar gastos', () {
      final summary = service.calculate(
        from: from,
        to: to,
        invoices: [
          _invoice(id: 'inv-1', numero: 1, fecha: DateTime(2026, 2, 10)),
        ],
        expenses: const [],
        assets: const [],
        gigs: const [],
        irpfRate: 0.15,
      );

      expect(summary.ingresosOficiales, 1000);
      expect(summary.ivaRepercutidoBruto, 210);
      expect(summary.ivaEstimadoAPagar, 210);
      // IRPF teórico bruto = 1000 * 0.15, sin IRPF adelantado.
      expect(summary.irpfAdelantado, 0);
      expect(summary.irpfEstimadoAPagar, closeTo(150, 0.001));
    });

    test('IRPF retenido por cliente: IRPF estimado = teórico − adelantado', () {
      // irpfRate 0.07 sobre 1000 => 70 adelantado por el cliente.
      final summary = service.calculate(
        from: from,
        to: to,
        invoices: [
          _invoice(
            id: 'inv-1',
            numero: 1,
            fecha: DateTime(2026, 2, 10),
            irpfRate: 0.07,
          ),
        ],
        expenses: const [],
        assets: const [],
        gigs: const [],
        irpfRate: 0.15,
      );

      expect(summary.irpfAdelantado, closeTo(70, 0.001));
      // 1000 * 0.15 - 70 = 80
      expect(summary.irpfEstimadoAPagar, closeTo(80, 0.001));
    });

    test('gastos e inversiones muy altos NO cambian IVA ni IRPF estimados', () {
      final invoices = [
        _invoice(id: 'inv-1', numero: 1, fecha: DateTime(2026, 2, 10)),
      ];

      final sinGastos = service.calculate(
        from: from,
        to: to,
        invoices: invoices,
        expenses: const [],
        assets: const [],
        gigs: const [],
        irpfRate: 0.15,
      );

      final conGastos = service.calculate(
        from: from,
        to: to,
        invoices: invoices,
        expenses: [
          Expense(
            fecha: DateTime(2026, 3, 1),
            concepto: 'Equipo caro',
            importeBase: 50000,
            ivaAmount: 0,
            total: 50000,
          ),
        ],
        assets: [
          Asset(
            descripcion: 'Furgoneta',
            fechaCompra: DateTime(2026, 1, 15),
            importeTotal: 30000,
            importeConIva: 36300,
            ivaRate: 21,
            ivaAmount: 6300,
            vidaUtilAnos: 6,
            createdAt: DateTime(2026, 1, 15),
          ),
        ],
        gigs: const [],
        irpfRate: 0.15,
      );

      expect(conGastos.ivaEstimadoAPagar, sinGastos.ivaEstimadoAPagar);
      expect(conGastos.irpfEstimadoAPagar, sinGastos.irpfEstimadoAPagar);
      // Los gastos e inversiones solo aparecen de forma informativa.
      expect(conGastos.totalGastosInversiones, closeTo(80000, 0.001));
    });

    test('periodo sin facturas: IVA e IRPF estimados a 0', () {
      final summary = service.calculate(
        from: from,
        to: to,
        invoices: const [],
        expenses: const [],
        assets: const [],
        gigs: const [],
        irpfRate: 0.15,
      );

      expect(summary.ivaEstimadoAPagar, 0);
      expect(summary.irpfEstimadoAPagar, 0);
    });

    test('las facturas en borrador no generan impuestos estimados', () {
      final summary = service.calculate(
        from: from,
        to: to,
        invoices: [
          _invoice(
            id: 'inv-1',
            numero: 1,
            fecha: DateTime(2026, 2, 10),
            status: InvoiceStatus.borrador,
          ),
        ],
        expenses: const [],
        assets: const [],
        gigs: const [],
        irpfRate: 0.15,
      );

      expect(summary.ivaEstimadoAPagar, 0);
      expect(summary.irpfEstimadoAPagar, 0);
    });
  });

  group('DriveDocumentSyncService.buildExpensePath', () {
    test('construye la ruta por trimestre y mes capitalizado', () {
      expect(
        DriveDocumentSyncService.buildExpensePath(DateTime(2026, 2, 10)),
        'MisBolos/2026/T1/Febrero/Gastos e Inversiones/',
      );
      expect(
        DriveDocumentSyncService.buildExpensePath(DateTime(2026, 5, 1)),
        'MisBolos/2026/T2/Mayo/Gastos e Inversiones/',
      );
      expect(
        DriveDocumentSyncService.buildExpensePath(DateTime(2026, 8, 20)),
        'MisBolos/2026/T3/Agosto/Gastos e Inversiones/',
      );
      expect(
        DriveDocumentSyncService.buildExpensePath(DateTime(2026, 11, 3)),
        'MisBolos/2026/T4/Noviembre/Gastos e Inversiones/',
      );
    });

    test('respeta años distintos', () {
      expect(
        DriveDocumentSyncService.buildExpensePath(DateTime(2025, 1, 1)),
        'MisBolos/2025/T1/Enero/Gastos e Inversiones/',
      );
    });
  });
}
