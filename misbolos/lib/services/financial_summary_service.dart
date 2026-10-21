import '../models/financial_summary.dart';
import '../models/gig.dart';
import '../models/invoice.dart';

class FinancialSummaryService {
  const FinancialSummaryService();

  /// Tipo del pago fraccionado de IRPF (modelo 130) en estimación directa.
  ///
  /// Es fijo por ley y no depende del tipo de retención de cada factura ni de
  /// `AppSettings.irpfDefault` (que solo es la retención por defecto al emitir).
  static const double irpfPagoFraccionadoRate = 0.20;

  /// Calcula una estimación fiscal BRUTA y orientativa del periodo.
  ///
  /// Solo depende de las facturas emitidas: los gastos e inversiones no entran.
  FinancialSummary calculate({
    required DateTime from,
    required DateTime to,
    required List<Invoice> invoices,
    required List<Gig> gigs,
  }) {
    final emittedInvoices = invoices
        .where(
          (invoice) =>
              invoice.status != InvoiceStatus.borrador &&
              _isWithin(invoice.fecha, from, to),
        )
        .toList();

    final ingresosOficiales = emittedInvoices.fold<double>(
      0.0,
      (sum, invoice) => sum + invoice.subtotal,
    );
    final ivaRepercutidoBruto = emittedInvoices.fold<double>(
      0.0,
      (sum, invoice) => sum + invoice.ivaAmount,
    );
    final irpfRetenido = emittedInvoices.fold<double>(
      0.0,
      (sum, invoice) => sum + invoice.irpfAmount,
    );

    final ingresosB = gigs
        .where(
          (gig) =>
              gig.facturable &&
              gig.status == GigStatus.cobrado &&
              (gig.invoiceId == null || gig.invoiceId!.isEmpty) &&
              _isWithin(gig.fecha, from, to),
        )
        .fold<double>(0.0, (sum, gig) => sum + (gig.cachet ?? 0.0));

    final irpfTeorico = ingresosOficiales * irpfPagoFraccionadoRate;
    final irpfAIngresar = irpfTeorico - irpfRetenido;

    return FinancialSummary(
      from: from,
      to: to,
      ingresosOficiales: ingresosOficiales,
      ingresosB: ingresosB,
      ivaRepercutidoBruto: ivaRepercutidoBruto,
      irpfTeorico: irpfTeorico,
      irpfRetenido: irpfRetenido,
      irpfAIngresar: irpfAIngresar > 0 ? irpfAIngresar : 0,
    );
  }

  bool _isWithin(DateTime date, DateTime from, DateTime to) {
    return !date.isBefore(from) && !date.isAfter(to);
  }
}
