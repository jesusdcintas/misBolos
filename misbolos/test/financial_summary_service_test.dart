import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/services/drive_document_sync_service.dart';
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
        gigs: const [],
      );

      expect(summary.ingresosOficiales, 1000);
      expect(summary.ivaRepercutidoBruto, 210);
      // IRPF teórico = 1000 * 20 %, sin retención.
      expect(summary.irpfRetenido, 0);
      expect(summary.irpfAIngresar, closeTo(200, 0.001));
    });

    test('IRPF retenido por cliente: a ingresar = teórico − retenido', () {
      // irpfRate 0.07 sobre 1000 => 70 retenido por el cliente.
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
        gigs: const [],
      );

      expect(summary.irpfRetenido, closeTo(70, 0.001));
      // 1000 * 0.20 - 70 = 130
      expect(summary.irpfAIngresar, closeTo(130, 0.001));
    });

    test('base 1.000 € con retención del 7 %: retenido 70, a ingresar 130, total 200', () {
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
        gigs: const [],
      );

      expect(summary.irpfRetenido, closeTo(70, 0.001));
      expect(summary.irpfAIngresar, closeTo(130, 0.001));
      expect(summary.irpfTotal, closeTo(200, 0.001));
      expect(summary.retencionSuperaIrpf, isFalse);
    });

    test('retención mayor que el 20 %: 0 € a ingresar y nota activada', () {
      final summary = service.calculate(
        from: from,
        to: to,
        invoices: [
          _invoice(
            id: 'inv-1',
            numero: 1,
            fecha: DateTime(2026, 2, 10),
            irpfRate: 0.25,
          ),
        ],
        gigs: const [],
      );

      expect(summary.irpfRetenido, closeTo(250, 0.001));
      expect(summary.irpfAIngresar, 0);
      expect(summary.irpfTotal, closeTo(250, 0.001));
      expect(summary.retencionSuperaIrpf, isTrue);
    });

    test('el tipo del pago fraccionado es un 20 % fijo', () {
      expect(FinancialSummaryService.irpfPagoFraccionadoRate, 0.20);
    });

    test('el servicio no recibe gastos: IVA e IRPF solo dependen de facturas', () {
      final invoices = [
        _invoice(id: 'inv-1', numero: 1, fecha: DateTime(2026, 2, 10)),
      ];

      final primera = service.calculate(
        from: from,
        to: to,
        invoices: invoices,
        gigs: const [],
      );
      final segunda = service.calculate(
        from: from,
        to: to,
        invoices: invoices,
        gigs: const [],
      );

      expect(segunda.ivaRepercutidoBruto, primera.ivaRepercutidoBruto);
      expect(segunda.irpfAIngresar, primera.irpfAIngresar);
    });

    test('periodo sin facturas: IVA e IRPF estimados a 0', () {
      final summary = service.calculate(
        from: from,
        to: to,
        invoices: const [],
        gigs: const [],
      );

      expect(summary.ivaRepercutidoBruto, 0);
      expect(summary.irpfAIngresar, 0);
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
        gigs: const [],
      );

      expect(summary.ivaRepercutidoBruto, 0);
      expect(summary.irpfAIngresar, 0);
    });
  });

  group('DriveDocumentSyncService.buildExpensePath', () {
    test('usa los nombres reales de las carpetas del sync', () {
      expect(
        DriveDocumentSyncService.buildExpensePath(DateTime(2026, 2, 10)),
        'Contabilidad 2026/1 TRIMESTRE/FEBRERO/Gastos e Inversiones',
      );
      expect(
        DriveDocumentSyncService.buildExpensePath(DateTime(2026, 5, 1)),
        'Contabilidad 2026/2 TRIMESTRE/MAYO/Gastos e Inversiones',
      );
      expect(
        DriveDocumentSyncService.buildExpensePath(DateTime(2026, 8, 20)),
        'Contabilidad 2026/3 TRIMESTRE/AGOSTO/Gastos e Inversiones',
      );
      expect(
        DriveDocumentSyncService.buildExpensePath(DateTime(2026, 11, 3)),
        'Contabilidad 2026/4 TRIMESTRE/NOVIEMBRE/Gastos e Inversiones',
      );
    });

    test('respeta años distintos', () {
      expect(
        DriveDocumentSyncService.buildExpensePath(DateTime(2025, 12, 31)),
        'Contabilidad 2025/4 TRIMESTRE/DICIEMBRE/Gastos e Inversiones',
      );
    });
  });

  group('DriveDocumentSyncService.expenseFolderChanged', () {
    test('mismo mes no cambia de carpeta', () {
      expect(
        DriveDocumentSyncService.expenseFolderChanged(
          DateTime(2026, 2, 1),
          DateTime(2026, 2, 28),
        ),
        isFalse,
      );
    });

    test('otro mes del mismo trimestre cambia de carpeta', () {
      expect(
        DriveDocumentSyncService.expenseFolderChanged(
          DateTime(2026, 1, 15),
          DateTime(2026, 3, 15),
        ),
        isTrue,
      );
    });

    test('otro trimestre y otro año cambian de carpeta', () {
      expect(
        DriveDocumentSyncService.expenseFolderChanged(
          DateTime(2026, 3, 31),
          DateTime(2026, 4, 1),
        ),
        isTrue,
      );
      expect(
        DriveDocumentSyncService.expenseFolderChanged(
          DateTime(2025, 2, 10),
          DateTime(2026, 2, 10),
        ),
        isTrue,
      );
    });
  });
}
