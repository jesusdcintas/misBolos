import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/period_utils.dart';
import '../models/financial_summary.dart';
import '../services/financial_summary_service.dart';
import 'assets_provider.dart';
import 'expenses_provider.dart';
import 'gig_provider.dart';
import 'invoice_provider.dart';
import 'stats_provider.dart';

final financialSummaryServiceProvider = Provider<FinancialSummaryService>(
  (ref) => const FinancialSummaryService(),
);

final financialSummaryProvider =
    FutureProvider.family<FinancialSummary, DashboardPeriod>((
      ref,
      period,
    ) async {
      final invoices = await ref.watch(invoicesProvider.future);
      final expenses = await ref.watch(expensesProvider.future);
      final assets = await ref.watch(assetsProvider.future);
      final gigs = await ref.watch(gigsProvider.future);
      final (from, to) = _periodRange(period);

      return ref
          .read(financialSummaryServiceProvider)
          .calculate(
            from: from,
            to: to,
            invoices: invoices,
            expenses: expenses,
            assets: assets,
            gigs: gigs,
          );
    });

(DateTime, DateTime) _periodRange(DashboardPeriod period) {
  switch (period.mode) {
    case DashboardPeriodMode.mes:
      return PeriodUtils.monthRange(period.year, period.month);
    case DashboardPeriodMode.trimestre:
      return PeriodUtils.quarterRange(period.year, period.quarter);
    case DashboardPeriodMode.anio:
      return PeriodUtils.yearRange(period.year);
  }
}
