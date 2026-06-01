import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/expense.dart';
import '../../models/financial_summary.dart';
import '../../models/gig.dart';
import '../../providers/expenses_provider.dart';
import '../../providers/assets_provider.dart';
import '../../providers/financial_summary_provider.dart';
import '../../providers/stats_provider.dart';
import '../../services/pdf_service.dart';
import '../../widgets/common/dj_refresh_indicator.dart';

class FinancialSummaryScreen extends ConsumerWidget {
  const FinancialSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(financialPeriodProvider);
    final summaryAsync = ref.watch(financialPeriodSummaryProvider(period));
    final fiscalAsync = ref.watch(financialSummaryProvider(period));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumen Financiero'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Descargar resumen',
            onPressed: () {
              final summary = summaryAsync.valueOrNull;
              if (summary != null) {
                _exportSummary(
                  context,
                  summary,
                  period,
                  fiscalAsync.valueOrNull,
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Period selectors
          _PeriodHeader(),
          const Divider(height: 1),

          Expanded(
            child: summaryAsync.when(
              data: (summary) => DJRefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(financialPeriodSummaryProvider(period));
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Main summary card
                    _SummaryCard(summary: summary),
                    const SizedBox(height: 16),

                    fiscalAsync.when(
                      data: (fiscal) => _FiscalSection(summary: fiscal),
                      loading: () => const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                      error: (e, _) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Error fiscal: $e'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // IVA section (quarter + year modes)
                    if (summary.ivaQuarters.isNotEmpty) ...[
                      _IvaSection(quarters: summary.ivaQuarters),
                      const SizedBox(height: 16),
                    ],

                    // Gastos section
                    _GastosSection(period: period),
                    const SizedBox(height: 16),

                    // Amortizaciones section
                    _AmortizacionSection(period: period),
                    const SizedBox(height: 16),

                    // Sub-period breakdown
                    if (period.mode != DashboardPeriodMode.mes &&
                        summary.subPeriods.isNotEmpty) ...[
                      _SubPeriodBreakdown(
                        subPeriods: summary.subPeriods,
                        year: period.year,
                        mode: period.mode,
                      ),
                    ],

                    // Gigs list for month mode
                    if (period.mode == DashboardPeriodMode.mes &&
                        summary.subPeriods.isNotEmpty &&
                        summary.subPeriods.first.gigs.isNotEmpty) ...[
                      _GigsList(gigs: summary.subPeriods.first.gigs),
                    ],

                    const SizedBox(height: 80),
                  ],
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportSummary(
    BuildContext context,
    FinancialPeriodSummary summary,
    DashboardPeriod period,
    FinancialSummary? fiscalSummary,
  ) async {
    try {
      final file = await PdfService().generateSummaryPdf(
        summary: summary,
        fiscalSummary: fiscalSummary,
      );
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al generar PDF: $e')));
      }
    }
  }
}

// ==================== FISCAL SECTION ====================

class _FiscalSection extends StatelessWidget {
  final FinancialSummary summary;

  const _FiscalSection({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fiscalidad estimada',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              summary.hasEstimatedHistoricalData
                  ? 'Incluye histórico estimado desde bolos facturables sin factura'
                  : 'Calculado con facturas cobradas, gastos e inversiones',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const Divider(height: 24),
            _row(
              icon: Icons.receipt_long,
              color: AppColors.primary,
              label: 'Ingresos oficiales',
              value: summary.ingresosOficiales,
            ),
            const SizedBox(height: 12),
            _row(
              icon: Icons.account_balance,
              color: AppColors.warning,
              label: 'IVA repercutido',
              value: summary.ivaRepercutido,
            ),
            const SizedBox(height: 12),
            _row(
              icon: Icons.savings,
              color: AppColors.success,
              label: 'IVA soportado deducible',
              value: summary.ivaSoportado,
            ),
            const SizedBox(height: 12),
            _row(
              icon: Icons.payments,
              color: summary.ivaAPagar >= 0
                  ? AppColors.warning
                  : AppColors.success,
              label: summary.ivaAPagar >= 0 ? 'IVA a pagar' : 'IVA a compensar',
              value: summary.ivaAPagar.abs(),
            ),
            const Divider(height: 24),
            _row(
              icon: Icons.category,
              color: AppColors.textSecondary,
              label: 'Gastos deducibles',
              value: summary.gastosDeducibles,
            ),
            const SizedBox(height: 12),
            _row(
              icon: Icons.trending_down,
              color: AppColors.textSecondary,
              label: 'Amortización',
              value: summary.amortizacion,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _row(
                icon: Icons.insights,
                color: AppColors.primary,
                label: 'Beneficio estimado',
                value: summary.beneficioEstimado,
                large: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required Color color,
    required String label,
    required double value,
    bool large = false,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: large ? 24 : 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: large ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
        Text(
          CurrencyFormatter.format(value),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: large ? 18 : 15,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ==================== PERIOD HEADER ====================

class _PeriodHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(financialPeriodProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          // Mode toggle
          Container(
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: DashboardPeriodMode.values.map((mode) {
                final isSelected = period.mode == mode;
                final label = switch (mode) {
                  DashboardPeriodMode.mes => 'Mes',
                  DashboardPeriodMode.trimestre => 'Trimestre',
                  DashboardPeriodMode.anio => 'Año',
                };
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      ref.read(financialPeriodProvider.notifier).state = period
                          .copyWith(mode: mode);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Period navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 28),
                onPressed: () {
                  ref.read(financialPeriodProvider.notifier).state =
                      period.previous;
                },
              ),
              GestureDetector(
                onTap: () {
                  final now = DateTime.now();
                  ref
                      .read(financialPeriodProvider.notifier)
                      .state = DashboardPeriod(
                    mode: period.mode,
                    year: now.year,
                    month: now.month,
                    quarter: ((now.month - 1) ~/ 3) + 1,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    period.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  size: 28,
                  color: period.isFuture ? AppColors.cardBorder : null,
                ),
                onPressed: period.isFuture
                    ? null
                    : () {
                        ref.read(financialPeriodProvider.notifier).state =
                            period.next;
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==================== SUMMARY CARD ====================

class _SummaryCard extends StatelessWidget {
  final FinancialPeriodSummary summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final totalCobrado = summary.cobrado;
    final progress = summary.totalPrevistoGlobal > 0
        ? (totalCobrado / summary.totalPrevistoGlobal).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen · ${summary.period.label}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.numBolos} bolos · ${summary.numFacturasPagadas} facturas cobradas · ${summary.pendienteCount} pendientes de cobro',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const Divider(height: 24),

            // Cobrado oficial
            _statRow(
              icon: Icons.check_circle,
              color: AppColors.success,
              label: 'Cobrado (Facturas)',
              value: summary.cobradoFacturas,
            ),

            if (summary.cobradoHistorico > 0) ...[
              const SizedBox(height: 14),
              _statRow(
                icon: Icons.history,
                color: AppColors.success,
                label: 'Cobrado (Histórico)',
                value: summary.cobradoHistorico,
              ),
            ],
            const SizedBox(height: 14),

            // Pendiente
            _statRow(
              icon: Icons.schedule,
              color: AppColors.warning,
              label: 'Pendiente de cobro',
              value: summary.pendiente,
            ),
            const SizedBox(height: 14),

            // Eventos privados
            _statRow(
              icon: Icons.money_off,
              color: AppColors.purple,
              label: 'Cobrado privado',
              value: summary.cobradoEnB,
            ),

            if (summary.pendienteEnB > 0) ...[
              const SizedBox(height: 14),
              _statRow(
                icon: Icons.hourglass_empty,
                color: AppColors.purple,
                label: 'Pendiente de cobro privado',
                value: summary.pendienteEnB,
              ),
            ],

            if (summary.previstoEnB > 0) ...[
              const SizedBox(height: 14),
              _statRow(
                icon: Icons.event_available,
                color: AppColors.purple,
                label: 'Previsto privado',
                value: summary.previstoEnB,
              ),
            ],

            if (summary.previsto > 0) ...[
              const SizedBox(height: 14),
              _statRow(
                icon: Icons.event_available,
                color: AppColors.primary,
                label: 'Previsto',
                value: summary.previsto,
              ),
            ],

            const Divider(height: 28),

            // Total previsto + progress
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.trending_up,
                        color: AppColors.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TOTAL PREVISTO',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(
                                summary.totalPrevistoGlobal,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: AppColors.cardBorder,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.success,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(progress * 100).toStringAsFixed(1)}% cobrado',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                      Text(
                        'Falta: ${CurrencyFormatter.format((summary.totalPrevistoGlobal - totalCobrado).clamp(0, double.infinity))}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Acumulado
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ACUMULADO',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(summary.acumuladoTotal),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  // Comparison
                  if (summary.prevCobradoTotal != null &&
                      summary.prevLabel != null) ...[
                    const SizedBox(height: 8),
                    _buildComparison(
                      totalCobrado,
                      summary.prevCobradoTotal!,
                      summary.prevLabel!,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow({
    required IconData icon,
    required Color color,
    required String label,
    required double value,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          CurrencyFormatter.format(value),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildComparison(double current, double prev, String label) {
    if (prev == 0 && current == 0) return const SizedBox.shrink();

    final pct = prev > 0 ? ((current - prev) / prev * 100).round() : 100;
    final isUp = pct >= 0;

    return Row(
      children: [
        Icon(
          isUp ? Icons.arrow_upward : Icons.arrow_downward,
          size: 14,
          color: isUp ? AppColors.success : AppColors.error,
        ),
        const SizedBox(width: 4),
        Text(
          'vs $label: ${CurrencyFormatter.format(prev)} · ${isUp ? '+' : ''}$pct%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isUp ? AppColors.success : AppColors.error,
          ),
        ),
      ],
    );
  }
}

// ==================== IVA SECTION ====================

class _IvaSection extends StatelessWidget {
  final List<QuarterVatDetail> quarters;
  const _IvaSection({required this.quarters});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'IVA Trimestral',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...quarters.map((q) => _IvaQuarterCard(quarter: q)),
      ],
    );
  }
}

class _IvaQuarterCard extends ConsumerWidget {
  final QuarterVatDetail quarter;
  const _IvaQuarterCard({required this.quarter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Status badge colors
    Color badgeBg;
    Color badgeText;
    String badgeLabel;

    switch (quarter.status) {
      case 'declarado':
        badgeBg = AppColors.successBg;
        badgeText = AppColors.success;
        badgeLabel = 'Declarado';
        break;
      case 'pendiente_declarar':
        badgeBg = AppColors.errorBg;
        badgeText = AppColors.error;
        badgeLabel = 'Sin declarar';
        break;
      case 'pasado':
        badgeBg = AppColors.successBg;
        badgeText = AppColors.success;
        badgeLabel = 'Declarado';
        break;
      case 'en_curso':
        badgeBg = AppColors.primaryLight;
        badgeText = AppColors.primary;
        badgeLabel = 'Actual';
        break;
      default:
        badgeBg = AppColors.draftBg;
        badgeText = AppColors.draft;
        badgeLabel = 'Futuro';
    }

    // Estimated badge
    Color estBadgeBg;
    Color estBadgeText;
    String estBadgeLabel;
    if (quarter.isEstimated) {
      estBadgeBg = const Color(0xFFF1EFE8);
      estBadgeText = const Color(0xFF5F5E5A);
      estBadgeLabel = 'Estimado';
    } else {
      estBadgeBg = const Color(0xFFE8F6EF);
      estBadgeText = const Color(0xFF1B8A56);
      estBadgeLabel = 'Real';
    }

    final declFormat = DateFormat('dd MMM', 'es');

    // Can toggle declared? Past quarters only (not en_curso or futuro)
    final canToggleDeclared =
        quarter.status == 'pendiente_declarar' ||
        quarter.status == 'pasado' ||
        quarter.status == 'declarado';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: badgeBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'T${quarter.quarter}',
            style: TextStyle(fontWeight: FontWeight.bold, color: badgeText),
          ),
        ),
        title: Row(
          children: [
            Text(
              CurrencyFormatter.format(quarter.ivaTotal),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: estBadgeBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                estBadgeLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: estBadgeText,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badgeLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: badgeText,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Declaración: ${declFormat.format(quarter.declarationDate)}${quarter.daysRemaining > 0 ? ' (${quarter.daysRemaining} días)' : ''}',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Invoice details
                if (quarter.invoices.isNotEmpty) ...[
                  const Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Factura',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Base',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'IVA',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  ...quarter.invoices.map(
                    (inv) => InkWell(
                      onTap: () => context.push('/invoice/${inv.invoiceId}'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '#${inv.numero} · ${inv.clientName}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    DateFormat('dd/MM/yy').format(inv.fecha),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                CurrencyFormatter.format(inv.base),
                                style: const TextStyle(fontSize: 12),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                CurrencyFormatter.format(inv.iva),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (quarter.ivaFacturas > 0) ...[
                    const Divider(height: 12),
                    Row(
                      children: [
                        const Expanded(
                          flex: 3,
                          child: Text(
                            'IVA facturas',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                            CurrencyFormatter.format(quarter.ivaFacturas),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],

                // Historical estimated IVA section
                if (quarter.isEstimated) ...[
                  if (quarter.invoices.isNotEmpty) const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1EFE8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'IVA estimado (histórico)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF5F5E5A),
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(
                                quarter.ivaHistoricoEstimado,
                              ),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5F5E5A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Base estimada: ${CurrencyFormatter.format(quarter.ivaHistoricoEstimado / 0.21 * 1.21)} · IVA 21%',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF5F5E5A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'IVA calculado sobre el cachet de los bolos importados. Puede diferir del IVA real declarado.',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (quarter.invoices.isEmpty && !quarter.isEstimated)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Sin facturas cobradas en este trimestre',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),

                // Total
                if (quarter.ivaTotal > 0) ...[
                  const Divider(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        flex: 3,
                        child: Text(
                          'Total IVA',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          CurrencyFormatter.format(quarter.ivaTotal),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],

                // Declare button (past quarters only)
                if (canToggleDeclared) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: quarter.isDeclared
                        ? Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.successBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: AppColors.success,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Declarado ✓',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.success,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: () {
                                    ref
                                        .read(declaredQuartersProvider.notifier)
                                        .toggle(
                                          quarter.year,
                                          quarter.quarter,
                                          ivaAmount: quarter.ivaTotal,
                                        );
                                    // Invalidate financial summary
                                    ref.invalidate(
                                      financialPeriodSummaryProvider,
                                    );
                                  },
                                  child: const Text(
                                    'Deshacer',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: () {
                              ref
                                  .read(declaredQuartersProvider.notifier)
                                  .toggle(
                                    quarter.year,
                                    quarter.quarter,
                                    ivaAmount: quarter.ivaTotal,
                                  );
                              // Invalidate financial summary
                              ref.invalidate(financialPeriodSummaryProvider);
                            },
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Marcar como declarado'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== SUB-PERIOD BREAKDOWN ====================

class _SubPeriodBreakdown extends StatelessWidget {
  final List<SubPeriodStats> subPeriods;
  final int year;
  final DashboardPeriodMode mode;
  const _SubPeriodBreakdown({
    required this.subPeriods,
    required this.year,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          mode == DashboardPeriodMode.anio
              ? 'Desglose por Meses'
              : 'Desglose por Meses',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...subPeriods.map((sp) => _SubPeriodCard(stats: sp, year: year)),
      ],
    );
  }
}

class _SubPeriodCard extends StatelessWidget {
  final SubPeriodStats stats;
  final int year;
  const _SubPeriodCard({required this.stats, required this.year});

  @override
  Widget build(BuildContext context) {
    if (!stats.hasData) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                stats.label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[500],
                ),
              ),
            ),
          ),
          title: Text(
            'Sin actividad',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              stats.label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        title: Text(
          'Total previsto: ${CurrencyFormatter.format(stats.totalPrevistoGlobal)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Cobrado: ${CurrencyFormatter.format(stats.total)}',
          style: const TextStyle(color: AppColors.success, fontSize: 13),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow(
                  'Cobrado (facturas)',
                  stats.cobrado,
                  AppColors.success,
                ),
                if (stats.cobradoHistorico > 0)
                  _detailRow(
                    'Cobrado (histórico)',
                    stats.cobradoHistorico,
                    AppColors.success,
                  ),
                _detailRow(
                  'Pendiente de cobro',
                  stats.pendiente,
                  AppColors.warning,
                ),
                _detailRow(
                  'Cobrado privado',
                  stats.cobradoEnB,
                  AppColors.purple,
                ),
                if (stats.pendienteEnB > 0)
                  _detailRow(
                    'Pendiente de cobro privado',
                    stats.pendienteEnB,
                    AppColors.purple,
                  ),
                if (stats.previsto > 0)
                  _detailRow('Previsto', stats.previsto, AppColors.primary),
                if (stats.previstoEnB > 0)
                  _detailRow(
                    'Previsto privado',
                    stats.previstoEnB,
                    AppColors.purple,
                  ),
                const Divider(),
                _detailRow(
                  'Total previsto',
                  stats.totalPrevistoGlobal,
                  AppColors.primary,
                  bold: true,
                ),
                const SizedBox(height: 8),

                // Gigs
                if (stats.gigs.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.music_note,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${stats.numBolos} bolos',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...stats.gigs.map(
                    (gig) => InkWell(
                      onTap: () => context.push('/gig/${gig.gigId}'),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    gig.clientName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    DateFormat(
                                      'dd MMM',
                                      'es',
                                    ).format(gig.fecha),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(gig.importe),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _statusPill(gig.status),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    double value,
    Color color, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            CurrencyFormatter.format(value),
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(GigStatus status) {
    Color bg;
    Color text;
    switch (status) {
      case GigStatus.cobrado:
        bg = AppColors.successBg;
        text = AppColors.success;
        break;
      case GigStatus.cobradoB:
        bg = AppColors.purpleBg;
        text = AppColors.purple;
        break;
      case GigStatus.facturado:
      case GigStatus.confirmado:
      case GigStatus.confirmadoB:
      case GigStatus.realizadoB:
        bg = AppColors.warningBg;
        text = AppColors.warning;
        break;
      case GigStatus.cancelado:
        bg = AppColors.errorBg;
        text = AppColors.error;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
    );
  }
}

// ==================== GIGS LIST (month mode) ====================

class _GigsList extends StatelessWidget {
  final List<MonthlyGigDetail> gigs;
  const _GigsList({required this.gigs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.music_note, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              '${gigs.length} bolos',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...gigs.map(
          (gig) => Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              onTap: () => context.push('/gig/${gig.gigId}'),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: gig.status == GigStatus.cobradoB
                      ? AppColors.purpleBg
                      : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.music_note_outlined,
                  size: 20,
                  color: gig.status == GigStatus.cobradoB
                      ? AppColors.purple
                      : AppColors.primary,
                ),
              ),
              title: Text(
                gig.clientName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                DateFormat('dd MMM yyyy', 'es').format(gig.fecha),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    CurrencyFormatter.format(gig.importe),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusPill(gig.status),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusPill(GigStatus status) {
    Color bg;
    Color text;
    switch (status) {
      case GigStatus.cobrado:
        bg = AppColors.successBg;
        text = AppColors.success;
        break;
      case GigStatus.cobradoB:
        bg = AppColors.purpleBg;
        text = AppColors.purple;
        break;
      case GigStatus.facturado:
      case GigStatus.confirmado:
      case GigStatus.confirmadoB:
      case GigStatus.realizadoB:
        bg = AppColors.warningBg;
        text = AppColors.warning;
        break;
      case GigStatus.cancelado:
        bg = AppColors.errorBg;
        text = AppColors.error;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
    );
  }
}

// ==================== GASTOS SECTION ====================

class _GastosSection extends ConsumerWidget {
  final DashboardPeriod period;

  const _GastosSection({required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quarters = _quartersForPeriod(period);
    if (quarters.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gastos',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...quarters.map((q) => _GastosQuarterCard(year: q.$1, quarter: q.$2)),
      ],
    );
  }

  List<(int, int)> _quartersForPeriod(DashboardPeriod p) {
    switch (p.mode) {
      case DashboardPeriodMode.trimestre:
        return [(p.year, p.quarter)];
      case DashboardPeriodMode.anio:
        return [(p.year, 1), (p.year, 2), (p.year, 3), (p.year, 4)];
      case DashboardPeriodMode.mes:
        final q = ((p.month - 1) ~/ 3) + 1;
        return [(p.year, q)];
    }
  }
}

class _GastosQuarterCard extends ConsumerWidget {
  final int year;
  final int quarter;

  const _GastosQuarterCard({required this.year, required this.quarter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = (year: year, quarter: quarter);
    final totalesAsync = ref.watch(gastosTrimestralProvider(params));
    final ivaAsync = ref.watch(ivaDeducibleTrimestralProvider(params));
    final fmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');

    final totalGastos =
        totalesAsync.valueOrNull?.values.fold(0.0, (s, v) => s + v) ?? 0.0;
    final ivaSoportado = ivaAsync.valueOrNull ?? 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.warningBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'T$quarter',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.warning,
            ),
          ),
        ),
        title: totalesAsync.when(
          loading: () => const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (_, __) => const Text('Error'),
          data: (_) => Text(
            fmt.format(totalGastos),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        subtitle: ivaAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (_) => Text(
            'IVA soportado: ${fmt.format(ivaSoportado)}',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        children: [
          totalesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $e'),
            ),
            data: (totales) {
              if (totales.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'Sin gastos en este trimestre',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 8),
                    ...totales.entries.map((entry) {
                      final cat = ExpenseCategoryExtension.fromDb(entry.key);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(cat.label)),
                            Text(
                              fmt.format(entry.value),
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'IVA soportado deducible',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          fmt.format(ivaSoportado),
                          style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ==================== AMORTIZACIÓN SECTION ====================

class _AmortizacionSection extends ConsumerWidget {
  final DashboardPeriod period;

  const _AmortizacionSection({required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quarters = _quartersForPeriod(period);
    if (quarters.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Amortizaciones',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...quarters.map(
          (q) => _AmortizacionQuarterCard(year: q.$1, quarter: q.$2),
        ),
      ],
    );
  }

  List<(int, int)> _quartersForPeriod(DashboardPeriod p) {
    switch (p.mode) {
      case DashboardPeriodMode.trimestre:
        return [(p.year, p.quarter)];
      case DashboardPeriodMode.anio:
        return [(p.year, 1), (p.year, 2), (p.year, 3), (p.year, 4)];
      case DashboardPeriodMode.mes:
        final q = ((p.month - 1) ~/ 3) + 1;
        return [(p.year, q)];
    }
  }
}

class _AmortizacionQuarterCard extends ConsumerWidget {
  final int year;
  final int quarter;

  const _AmortizacionQuarterCard({required this.year, required this.quarter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = (year: year, quarter: quarter);
    final totalAsync = ref.watch(assetAmortizacionTrimestreProvider(params));
    final assetsAsync = ref.watch(assetsActivosProvider);
    final fmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'T$quarter',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ),
        title: totalAsync.when(
          loading: () => const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (_, __) => const Text('Error'),
          data: (total) => Text(
            fmt.format(total),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        subtitle: const Text(
          'Amortización acumulada',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        children: [
          assetsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $e'),
            ),
            data: (assets) {
              final activos = assets.where((a) {
                return a.cuotaTrimestreConcreto(year, quarter) > 0;
              }).toList();

              if (activos.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'Sin amortizaciones en este trimestre',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 8),
                    ...activos.map(
                      (a) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              a.categoria.icono,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                a.descripcion,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Text(
                              fmt.format(
                                a.cuotaTrimestreConcreto(year, quarter),
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Deducible de IRPF',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        totalAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                          data: (total) => Text(
                            fmt.format(total),
                            style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
