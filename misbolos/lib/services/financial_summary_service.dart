import '../models/asset.dart';
import '../models/expense.dart';
import '../models/financial_summary.dart';
import '../models/gig.dart';
import '../models/invoice.dart';

class FinancialSummaryService {
  const FinancialSummaryService();

  /// Calcula una estimación fiscal BRUTA y orientativa del periodo.
  ///
  /// No se restan gastos ni inversiones de los impuestos. [irpfRate] es el tipo
  /// de IRPF teórico aplicado sobre los ingresos oficiales (p. ej. 0.15).
  FinancialSummary calculate({
    required DateTime from,
    required DateTime to,
    required List<Invoice> invoices,
    required List<Expense> expenses,
    required List<Asset> assets,
    required List<Gig> gigs,
    double irpfRate = 0.15,
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
    final irpfAdelantado = emittedInvoices.fold<double>(
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

    final totalGastos = expenses
        .where((expense) => _isWithin(expense.fecha, from, to))
        .fold<double>(0.0, (sum, expense) => sum + expense.total);
    final totalInversiones = assets
        .where((asset) => _isWithin(asset.fechaCompra, from, to))
        .fold<double>(0.0, (sum, asset) => sum + asset.importeTotal);

    // IRPF teórico bruto sobre ingresos menos el ya retenido por los clientes.
    // Estimación orientativa, no cálculo fiscal real.
    final irpfEstimadoAPagar = ingresosOficiales * irpfRate - irpfAdelantado;

    return FinancialSummary(
      from: from,
      to: to,
      ingresosOficiales: ingresosOficiales,
      ingresosB: ingresosB,
      totalGastosInversiones: totalGastos + totalInversiones,
      ivaRepercutidoBruto: ivaRepercutidoBruto,
      irpfAdelantado: irpfAdelantado,
      ivaEstimadoAPagar: ivaRepercutidoBruto,
      irpfEstimadoAPagar: irpfEstimadoAPagar,
    );
  }

  bool _isWithin(DateTime date, DateTime from, DateTime to) {
    return !date.isBefore(from) && !date.isAfter(to);
  }
}
