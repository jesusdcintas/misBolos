import '../core/utils/period_utils.dart';
import '../models/asset.dart';
import '../models/expense.dart';
import '../models/financial_summary.dart';
import '../models/gig.dart';
import '../models/invoice.dart';

class FinancialSummaryService {
  const FinancialSummaryService();

  FinancialSummary calculate({
    required DateTime from,
    required DateTime to,
    required List<Invoice> invoices,
    required List<Expense> expenses,
    required List<Asset> assets,
    required List<Gig> gigs,
  }) {
    final quarters = _quartersInRange(from, to)
        .map(
          (q) => _calculateQuarter(
            year: q.$1,
            quarter: q.$2,
            invoices: invoices,
            expenses: expenses,
            assets: assets,
            gigs: gigs,
          ),
        )
        .toList();

    return FinancialSummary(
      from: from,
      to: to,
      ingresosFacturados: _sum(quarters, (q) => q.ingresosFacturados),
      ingresosHistoricosEstimados: _sum(
        quarters,
        (q) => q.ingresosHistoricosEstimados,
      ),
      ivaRepercutidoFacturas: _sum(quarters, (q) => q.ivaRepercutidoFacturas),
      ivaRepercutidoHistoricoEstimado: _sum(
        quarters,
        (q) => q.ivaRepercutidoHistoricoEstimado,
      ),
      gastosDeducibles: _sum(quarters, (q) => q.gastosDeducibles),
      ivaSoportadoGastos: _sum(quarters, (q) => q.ivaSoportadoGastos),
      ivaSoportadoInversiones: _sum(quarters, (q) => q.ivaSoportadoInversiones),
      amortizacion: _sum(quarters, (q) => q.amortizacion),
      quarters: quarters,
    );
  }

  FinancialQuarterSummary _calculateQuarter({
    required int year,
    required int quarter,
    required List<Invoice> invoices,
    required List<Expense> expenses,
    required List<Asset> assets,
    required List<Gig> gigs,
  }) {
    final (from, to) = PeriodUtils.quarterRange(year, quarter);
    final paidInvoices = invoices
        .where(
          (invoice) =>
              invoice.status == InvoiceStatus.pagada &&
              _isWithin(invoice.fecha, from, to),
        )
        .toList();
    final quarterExpenses = expenses
        .where((expense) => _isWithin(expense.fecha, from, to))
        .toList();
    final quarterAssetPurchases = assets
        .where((asset) => _isWithin(asset.fechaCompra, from, to))
        .toList();
    final historicalGigs = gigs
        .where(
          (gig) =>
              gig.facturable &&
              gig.status == GigStatus.pagado &&
              (gig.invoiceId == null || gig.invoiceId!.isEmpty) &&
              _isWithin(gig.fecha, from, to),
        )
        .toList();

    final historicalGross = historicalGigs.fold<double>(
      0.0,
      (sum, gig) => sum + (gig.cachet ?? 0.0),
    );
    final historicalBase = historicalGross > 0 ? historicalGross / 1.21 : 0.0;
    final historicalVat = historicalGross - historicalBase;

    return FinancialQuarterSummary(
      year: year,
      quarter: quarter,
      ingresosFacturados: paidInvoices.fold(
        0.0,
        (sum, invoice) => sum + invoice.subtotal,
      ),
      ingresosHistoricosEstimados: historicalBase,
      ivaRepercutidoFacturas: paidInvoices.fold(
        0.0,
        (sum, invoice) => sum + invoice.ivaAmount,
      ),
      ivaRepercutidoHistoricoEstimado: historicalVat,
      gastosDeducibles: quarterExpenses.fold(
        0.0,
        (sum, expense) => sum + _deductibleBase(expense),
      ),
      ivaSoportadoGastos: quarterExpenses.fold(
        0.0,
        (sum, expense) => sum + _deductibleVat(expense),
      ),
      ivaSoportadoInversiones: quarterAssetPurchases.fold(
        0.0,
        (sum, asset) => sum + _assetVat(asset),
      ),
      amortizacion: assets.fold(
        0.0,
        (sum, asset) => sum + asset.cuotaTrimestreConcreto(year, quarter),
      ),
    );
  }

  List<(int, int)> _quartersInRange(DateTime from, DateTime to) {
    final result = <(int, int)>[];
    var year = from.year;
    var quarter = PeriodUtils.currentQuarter(from);
    while (year < to.year ||
        (year == to.year && quarter <= PeriodUtils.currentQuarter(to))) {
      result.add((year, quarter));
      if (quarter == 4) {
        year++;
        quarter = 1;
      } else {
        quarter++;
      }
    }
    return result;
  }

  bool _isWithin(DateTime date, DateTime from, DateTime to) {
    return !date.isBefore(from) && !date.isAfter(to);
  }

  double _deductibleBase(Expense expense) {
    if (!expense.esDeducible) return 0.0;
    return expense.importeBase * (expense.porcentajeDeduccion / 100);
  }

  double _deductibleVat(Expense expense) {
    if (!expense.esDeducible) return 0.0;
    return expense.ivaAmount * (expense.porcentajeDeduccion / 100);
  }

  double _assetVat(Asset asset) {
    if (asset.ivaAmount > 0) return asset.ivaAmount;
    return asset.ivaDeducible;
  }

  double _sum(
    List<FinancialQuarterSummary> quarters,
    double Function(FinancialQuarterSummary quarter) selector,
  ) {
    return quarters.fold(0.0, (sum, quarter) => sum + selector(quarter));
  }
}
