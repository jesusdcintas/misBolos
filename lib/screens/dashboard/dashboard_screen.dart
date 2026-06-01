import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/gig.dart';
import '../../providers/gig_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/stats_provider.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/facturable_badge.dart';
import '../../widgets/common/skeleton_loading.dart';
import '../../widgets/common/dismissible_alert_banner.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/dashboard/summary_card.dart';
import '../../widgets/common/expandable_fab.dart';
import '../../widgets/common/animated_counter.dart';
import '../../widgets/common/dj_refresh_indicator.dart';
import 'package:go_router/go_router.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(dashboardPeriodProvider);
    final statsAsync = ref.watch(periodDashboardStatsProvider(period));
    final upcomingAsync = ref.watch(upcomingGigsProvider);
    final recentAsync = ref.watch(recentGigsProvider);
    final overdueAsync = ref.watch(overdueInvoicesProvider);
    final activityAsync = ref.watch(activityStreakProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.dashboard),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Resumen Financiero',
            onPressed: () => context.push('/financial'),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Estadísticas',
            onPressed: () => context.push('/stats'),
          ),
        ],
      ),
      body: DJRefreshIndicator(
        onRefresh: () async {
          ref.invalidate(periodDashboardStatsProvider(period));
          ref.invalidate(upcomingGigsProvider);
          ref.invalidate(recentGigsProvider);
          ref.invalidate(overdueInvoicesProvider);
          ref.invalidate(activityStreakProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Period selector
            _PeriodSelector(),
            const SizedBox(height: 16),

            // Overdue banner
            overdueAsync.when(
              data: (alert) {
                if (alert.invoices.isEmpty) return const SizedBox.shrink();
                return DismissibleAlertBanner(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _OverdueBanner(alert: alert),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // Main stats
            statsAsync.when(
              data: (stats) => _buildStats(context, ref, stats, period),
              loading: () => const DashboardSkeleton(),
              error: (e, _) => Text('Error: $e'),
            ),

            const SizedBox(height: 24),

            // Upcoming gigs
            upcomingAsync.when(
              data: (upcoming) => _buildUpcomingGigs(context, upcoming),
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
            ),

            const SizedBox(height: 24),

            // Recent gigs
            Text(
              AppStrings.ultimosBolos,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            recentAsync.when(
              data: (gigs) {
                if (gigs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.music_off,
                    message: AppStrings.sinBolos,
                  );
                }
                return Column(
                  children: gigs.map((g) => _GigTile(gig: g)).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
            ),

            const SizedBox(height: 16),

            // Activity streak
            activityAsync.when(
              data: (activity) => _ActivityCard(activity: activity),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: ExpandableFAB(
        actions: [
          FABAction(
            icon: Icons.music_note,
            label: 'Nuevo bolo',
            color: AppColors.primary,
            onTap: (ctx) => ctx.push('/gig/new'),
          ),
          FABAction(
            icon: Icons.person_add,
            label: 'Nuevo cliente',
            color: AppColors.purple,
            onTap: (ctx) => ctx.push('/client/new'),
          ),
          FABAction(
            icon: Icons.euro_outlined,
            label: 'Nuevo gasto',
            color: AppColors.warning,
            onTap: (ctx) => ctx.push('/expense/new'),
          ),
          FABAction(
            icon: Icons.inventory_2_outlined,
            label: 'Nueva inversión',
            color: AppColors.success,
            onTap: (ctx) => ctx.push('/asset/new'),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(
    BuildContext context,
    WidgetRef ref,
    PeriodDashboardStats stats,
    DashboardPeriod period,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Financial summary banner
        _FinancialBanner(stats: stats, period: period),
        const SizedBox(height: 16),

        // Ingresos oficiales
        Text(
          AppStrings.ingresosOficiales,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                title: 'Cobrado',
                value: CurrencyFormatter.format(stats.cobradoOficial),
                numericValue: stats.cobradoOficial,
                color: AppColors.success,
                icon: Icons.check_circle_outline,
                showChevron: true,
                onTap: () => context.push('/financial'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '(facturas: ${CurrencyFormatter.format(stats.cobradoFacturas)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8C95A6),
                      ),
                    ),
                    Text(
                      ' + histórico: ${CurrencyFormatter.format(stats.cobradoHistorico)})',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8C95A6),
                      ),
                    ),
                    _buildComparison(
                      stats.cobradoOficial,
                      stats.prevCobrado,
                      stats.prevLabel,
                    ),
                  ],
                ),
                onInfoTap: () => _showMetricInfo(
                  context,
                  'Cobrado',
                  'Dinero ya recibido.\n· Facturas marcadas como pagadas\n· Bolos históricos importados sin factura\n· Cobros privados confirmados',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SummaryCard(
                title: 'Pendiente de cobro',
                value: CurrencyFormatter.format(stats.pendiente),
                numericValue: stats.pendiente,
                color: AppColors.warning,
                icon: Icons.schedule,
                showChevron: true,
                onTap: () => context.go('/finanzas'),
                subtitle: Text(
                  '(${stats.pendienteCount} factura${stats.pendienteCount == 1 ? '' : 's'} emitida${stats.pendienteCount == 1 ? '' : 's'} sin cobrar)',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8C95A6),
                  ),
                ),
                onInfoTap: () => _showMetricInfo(
                  context,
                  'Pendiente de cobro',
                  'Trabajo realizado con factura enviada\nal cliente, a la espera de que paguen.\nNo incluye bolos sin factura emitida.',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // CONFIRMADO (solo si > 0)
        if (stats.previstoConfirmado > 0) ...[
          SummaryCard(
            title: 'Confirmado',
            value: CurrencyFormatter.format(stats.previstoConfirmado),
            numericValue: stats.previstoConfirmado,
            color: AppColors.primary,
            icon: Icons.event_available,
            backgroundColor: const Color(0xFFEEF1F7),
            subtitle: Text(
              '(${stats.previstoConfirmadoCount} bolo${stats.previstoConfirmadoCount == 1 ? '' : 's'} confirmado${stats.previstoConfirmadoCount == 1 ? '' : 's'} en agenda\n aún no realizado${stats.previstoConfirmadoCount == 1 ? '' : 's'} ni facturado${stats.previstoConfirmadoCount == 1 ? '' : 's'})',
              style: const TextStyle(fontSize: 11, color: Color(0xFF8C95A6)),
            ),
                onInfoTap: () => _showMetricInfo(
              context,
              'Confirmado',
              'Bolos que tienes en agenda confirmados\npero que aún no has realizado ni facturado.\nEs dinero esperado, puede cambiar.',
            ),
          ),
          const SizedBox(height: 8),
        ],

        // ACUMULADO + TOTAL PREVISTO
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                title: 'Acumulado',
                value: CurrencyFormatter.format(stats.acumulado),
                numericValue: stats.acumulado,
                color: const Color(0xFF0F5C3A),
                icon: Icons.account_balance,
                subtitle: Text(
                  '(cobrado oficial ${CurrencyFormatter.format(stats.cobradoOficial)}\n + pendiente de cobro ${CurrencyFormatter.format(stats.pendiente)})',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8C95A6),
                  ),
                ),
                onInfoTap: () => _showMetricInfo(
                  context,
                  'Acumulado',
                  'Todo el trabajo ya ejecutado:\n· Cobrado: dinero recibido\n· Pendiente de cobro: facturas emitidas sin cobrar\nEs lo que has ganado hasta hoy.',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SummaryCard(
                title: 'Proyección oficial',
                value: CurrencyFormatter.format(stats.totalPrevisto),
                numericValue: stats.totalPrevisto,
                color: const Color(0xFF5F5E5A),
                icon: Icons.trending_up,
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '(acumulado ${CurrencyFormatter.format(stats.acumulado)}'
                      '\n + confirmado ${CurrencyFormatter.format(stats.previstoConfirmado)}'
                      '\n + borrador ${CurrencyFormatter.format(stats.previstoBorrador)})',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8C95A6),
                      ),
                    ),
                    const Text(
                      '· proyección',
                      style: TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF8C95A6),
                      ),
                    ),
                  ],
                ),
                onInfoTap: () => _showMetricInfo(
                  context,
                  'Proyección oficial',
                  'Proyección máxima del período:\n· Acumulado: trabajo ya hecho\n· Previsto: bolos futuros en agenda\nSolo se cumple si cobras todo y\nrealizas todos los bolos confirmados.',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // IVA
        if (stats.ivaTotalEstimado > 0 ||
            period.mode != DashboardPeriodMode.mes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SummaryCard(
              title: stats.ivaHistoricoEstimado > 0
                  ? 'IVA acumulado (estimado)'
                  : 'IVA acumulado',
              value: CurrencyFormatter.format(stats.ivaTotalEstimado),
              numericValue: stats.ivaTotalEstimado,
              color: AppColors.primary,
              icon: Icons.description_outlined,
              showChevron: true,
              onTap: () => context.push('/stats'),
              subtitle: stats.ivaHistoricoEstimado > 0
                  ? Text(
                      '(facturas: ${CurrencyFormatter.format(stats.ivaAcumulado)} + est. histórico: ${CurrencyFormatter.format(stats.ivaHistoricoEstimado)})',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8C95A6),
                      ),
                    )
                  : null,
            ),
          ),

        const SizedBox(height: 20),

        // Eventos privados
        Text(
          AppStrings.ingresosEnB,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.purple,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                title: 'Cobrado privado',
                value: CurrencyFormatter.format(stats.cobradoEnB),
                numericValue: stats.cobradoEnB,
                color: AppColors.purple,
                icon: Icons.money_off_outlined,
                showChevron: true,
                onTap: () => context.push('/financial'),
                subtitle: Text(
                  '(${stats.numBolosB} evento${stats.numBolosB == 1 ? '' : 's'} privado${stats.numBolosB == 1 ? '' : 's'})',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8C95A6),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SummaryCard(
                title: 'Pendiente de cobro privado',
                value: CurrencyFormatter.format(stats.pendienteEnB),
                numericValue: stats.pendienteEnB,
                color: AppColors.purple,
                icon: Icons.hourglass_empty_outlined,
                showChevron: true,
                onTap: () => context.push('/financial'),
                subtitle: Text(
                  '(${stats.pendienteEnBCount} evento${stats.pendienteEnBCount == 1 ? '' : 's'} privado${stats.pendienteEnBCount == 1 ? '' : 's'} realizado${stats.pendienteEnBCount == 1 ? '' : 's'} sin cobrar)',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8C95A6),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                title: 'Confirmado privado',
                value: CurrencyFormatter.format(stats.previstoEnB),
                numericValue: stats.previstoEnB,
                color: AppColors.purple,
                icon: Icons.account_balance,
                subtitle: Text(
                  '(${stats.previstoEnBCount} evento${stats.previstoEnBCount == 1 ? '' : 's'} privado${stats.previstoEnBCount == 1 ? '' : 's'} cerrado${stats.previstoEnBCount == 1 ? '' : 's'})',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8C95A6),
                  ),
                ),
                onInfoTap: () => _showMetricInfo(
                  context,
                  'Confirmado privado',
                  'Importe de eventos privados cerrados en agenda y aún no realizados.',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SummaryCard(
                title: 'Proyección privada',
                value: CurrencyFormatter.format(stats.totalPrevistoEnB),
                numericValue: stats.totalPrevistoEnB,
                color: AppColors.purple,
                icon: Icons.trending_up,
                subtitle: Text(
                  '(cobrado ${CurrencyFormatter.format(stats.cobradoEnB)}\n + pendiente ${CurrencyFormatter.format(stats.pendienteEnB)}\n + confirmado ${CurrencyFormatter.format(stats.previstoEnB)})',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8C95A6),
                  ),
                ),
                onInfoTap: () => _showMetricInfo(
                  context,
                  'Proyección privada',
                  'Suma total proyectada de eventos privados del período:\n· Cobrado privado\n· Realizado privado pendiente de cobro\n· Confirmado privado',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        Text(
          'Global',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                title: 'Cobrado total',
                value: CurrencyFormatter.format(stats.cobrado),
                numericValue: stats.cobrado,
                color: AppColors.success,
                icon: Icons.check_circle_outline,
                subtitle: Text(
                  '(oficial ${CurrencyFormatter.format(stats.cobradoOficial)}\n + privado ${CurrencyFormatter.format(stats.cobradoEnB)})',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8C95A6),
                  ),
                ),
                onInfoTap: () => _showMetricInfo(
                  context,
                  'Cobrado total',
                  'Total ya cobrado en el período sumando oficial y B.',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SummaryCard(
                title: 'Proyección global',
                value: CurrencyFormatter.format(stats.totalPrevistoGlobal),
                numericValue: stats.totalPrevistoGlobal,
                color: AppColors.warning,
                icon: Icons.schedule,
                subtitle: Text(
                  '(acumulado ${CurrencyFormatter.format(stats.acumuladoTotal)}'
                  '\n + confirmado ${CurrencyFormatter.format(stats.previstoConfirmado + stats.previstoEnB)}'
                  '\n + borrador ${CurrencyFormatter.format(stats.previstoBorrador)})',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8C95A6),
                  ),
                ),
                onInfoTap: () => _showMetricInfo(
                  context,
                  'Proyección global',
                  'Proyección combinada oficial + B:\n· Acumulado total (cobrado + pendiente de cobro)\n· Confirmado total (aún por realizar)',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (stats.previstoTotal > 0) ...[
          SummaryCard(
            title: 'Confirmado total',
            value: CurrencyFormatter.format(stats.previstoTotal),
            numericValue: stats.previstoTotal,
            color: AppColors.primary,
            icon: Icons.event_available,
            backgroundColor: const Color(0xFFEEF1F7),
            subtitle: Text(
              '(oficial ${CurrencyFormatter.format(stats.previsto)} + B ${CurrencyFormatter.format(stats.previstoEnB)})',
              style: const TextStyle(fontSize: 11, color: Color(0xFF8C95A6)),
            ),
            onInfoTap: () => _showMetricInfo(
              context,
              'Confirmado total',
                  'Suma de bolos confirmados aún no realizados en oficial y eventos privados.',
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                title: 'Acumulado total',
                value: CurrencyFormatter.format(stats.acumuladoTotal),
                numericValue: stats.acumuladoTotal,
                color: const Color(0xFF0F5C3A),
                icon: Icons.account_balance,
                onInfoTap: () => _showMetricInfo(
                  context,
                  'Acumulado total',
                  'Trabajo ya realizado en oficial y B:\n· Cobrado total\n· Pendiente de cobro total',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SummaryCard(
                title: 'Proyección global (máxima)',
                value: CurrencyFormatter.format(stats.totalPrevistoGlobal),
                numericValue: stats.totalPrevistoGlobal,
                color: const Color(0xFF5F5E5A),
                icon: Icons.trending_up,
                onInfoTap: () => _showMetricInfo(
                  context,
                  'Proyección global (máxima)',
                  'Escenario máximo si cobras todo lo realizado y además realizas todos los bolos confirmados.',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Total bolos
        SummaryCard(
          title: 'Bolos en el periodo',
          value: '${stats.totalBolos}',
          color: AppColors.primary,
          icon: Icons.music_note_outlined,
          showChevron: true,
          onTap: () => context.go('/calendar'),
          onInfoTap: () => _showMetricInfo(
            context,
            'Bolos en el período',
            'Cuenta total de bolos del período, excluyendo cancelados.',
          ),
        ),
      ],
    );
  }

  void _showMetricInfo(BuildContext context, String title, String explanation) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              explanation,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF5A6070),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparison(double current, double? previous, String? label) {
    if (previous == null || label == null) return const SizedBox.shrink();

    if (previous == 0 && current == 0) {
      return Text(
        '= igual que $label',
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      );
    }
    if (previous == 0) {
      return Text(
        '↑ nuevo vs $label',
        style: const TextStyle(fontSize: 11, color: Color(0xFF1B8A56)),
      );
    }

    final pct = ((current - previous) / previous * 100).round();
    if (pct == 0) {
      return Text(
        '= igual que $label',
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      );
    }

    final isUp = pct > 0;
    return Text(
      '${isUp ? '↑' : '↓'} ${isUp ? '+' : ''}$pct% vs $label',
      style: TextStyle(
        fontSize: 11,
        color: isUp ? const Color(0xFF1B8A56) : const Color(0xFFC0392B),
      ),
    );
  }

  Widget _buildUpcomingGigs(BuildContext context, List<Gig> upcoming) {
    final colors = context.colors;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final futureGigs = upcoming
        .where((g) {
          final gDate = DateTime(g.fecha.year, g.fecha.month, g.fecha.day);
          return !gDate.isBefore(today);
        })
        .take(3)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Próximos bolos',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (futureGigs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border, width: 0.6),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.event_available,
                  size: 40,
                  color: colors.textSecondary,
                ),
                const SizedBox(height: 8),
                Text(
                  'No tienes bolos programados',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => context.push('/gig/new'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Añadir bolo'),
                ),
              ],
            ),
          )
        else
          ...futureGigs.map((gig) {
            final gDate = DateTime(
              gig.fecha.year,
              gig.fecha.month,
              gig.fecha.day,
            );
            final daysLeft = gDate.difference(today).inDays;
            return _UpcomingGigTile(gig: gig, daysLeft: daysLeft);
          }),
      ],
    );
  }
}

// ==================== PERIOD SELECTOR ====================

class _PeriodSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;
    final period = ref.watch(dashboardPeriodProvider);

    return Column(
      children: [
        // Mode toggle: Mes / Trimestre / Año
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
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
                    ref.read(dashboardPeriodProvider.notifier).state = period
                        .copyWith(
                          mode: mode,
                          month: period.month,
                          quarter: period.quarter,
                          year: period.year,
                        );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : primary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        // Period navigation arrows + label
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 28),
              onPressed: () {
                ref.read(dashboardPeriodProvider.notifier).state =
                    period.previous;
              },
            ),
            GestureDetector(
              onTap: () {
                // Reset to current period
                final now = DateTime.now();
                ref
                    .read(dashboardPeriodProvider.notifier)
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
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  period.label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: primary,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.chevron_right,
                size: 28,
                color: period.isFuture ? colors.border : null,
              ),
              onPressed: period.isFuture
                  ? null
                  : () {
                      ref.read(dashboardPeriodProvider.notifier).state =
                          period.next;
                    },
            ),
          ],
        ),
      ],
    );
  }
}

// ==================== FINANCIAL BANNER ====================

class _FinancialBanner extends StatelessWidget {
  final PeriodDashboardStats stats;
  final DashboardPeriod period;
  const _FinancialBanner({required this.stats, required this.period});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => context.push('/financial'),
      child: Card(
        elevation: 2,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                primary,
                primary.withValues(alpha: 0.78),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Resumen · ${period.label}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white70),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _BannerMini(
                      label: 'Cobrado',
                      subtitle: '(oficial + B)',
                      value: stats.cobrado,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BannerMini(
                      label: 'Pendiente de cobro',
                      subtitle: '(oficial + B)',
                      value: stats.pendienteTotal,
                      color: colors.warningBg,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BannerMini(
                      label: 'Total previsto',
                      subtitle: '(si todo se cobra)',
                      value: stats.totalPrevistoGlobal,
                      color: colors.successBg,
                    ),
                  ),
                ],
              ),
              // Comparison under Cobrado only
              if (stats.prevCobrado != null && stats.prevLabel != null) ...[
                const SizedBox(height: 10),
                _buildBannerComparison(stats),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBannerComparison(PeriodDashboardStats stats) {
    final prev = stats.prevCobrado!;
    final current = stats.cobrado;
    if (prev == 0 && current == 0) return const SizedBox.shrink();

    final pct = prev > 0 ? ((current - prev) / prev * 100).round() : 100;
    final isUp = pct >= 0;

    return Text(
      '${isUp ? '↑' : '↓'} ${isUp ? '+' : ''}$pct% vs ${stats.prevLabel}',
      style: TextStyle(
        fontSize: 11,
        color: isUp ? Colors.greenAccent[100] : Colors.redAccent[100],
      ),
    );
  }
}

class _BannerMini extends StatelessWidget {
  final String label;
  final String? subtitle;
  final double value;
  final Color color;
  const _BannerMini({
    required this.label,
    this.subtitle,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11),
        ),
        const SizedBox(height: 2),
        AnimatedCounter(
          value: value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 1),
          Text(
            subtitle!,
            style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: 9),
          ),
        ],
      ],
    );
  }
}

// ==================== GIG TILES ====================

class _GigTile extends ConsumerWidget {
  final Gig gig;
  const _GigTile({required this.gig});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;
    final clientAsync = ref.watch(clientByIdProvider(gig.clientId));

    return Card(
      child: ListTile(
        onTap: () => context.push('/gig/${gig.id}'),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: gig.facturable ? colors.infoBg : AppColors.purpleBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.music_note_outlined,
            color: gig.facturable ? primary : AppColors.purple,
            size: 22,
          ),
        ),
        title: clientAsync.when(
          data: (client) => Text(
            client?.nombre ?? 'Cliente desconocido',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          loading: () => const Text('...'),
          error: (_, __) => const Text('Error'),
        ),
        subtitle: Text(
          '${DateFormatter.display(gig.fecha)}${gig.cachet != null ? ' · ${CurrencyFormatter.format(gig.cachet!)}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusBadge(status: gig.status, facturable: gig.facturable),
      ),
    );
  }
}

class _UpcomingGigTile extends ConsumerWidget {
  final Gig gig;
  final int daysLeft;
  const _UpcomingGigTile({required this.gig, required this.daysLeft});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;
    final clientAsync = ref.watch(clientByIdProvider(gig.clientId));

    String badgeText;
    Color badgeBg;
    Color badgeTextColor;
    if (daysLeft == 0) {
      badgeText = 'hoy';
      badgeBg = AppColors.successBg;
      badgeTextColor = AppColors.success;
    } else if (daysLeft == 1) {
      badgeText = 'mañana';
      badgeBg = AppColors.warningBg;
      badgeTextColor = AppColors.warning;
    } else {
      badgeText = 'en $daysLeft días';
      badgeBg = colors.infoBg;
      badgeTextColor = primary;
    }

    return Card(
      child: ListTile(
        onTap: () => context.push('/gig/${gig.id}'),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: gig.facturable ? colors.infoBg : AppColors.purpleBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.music_note_outlined,
            color: gig.facturable ? primary : AppColors.purple,
            size: 22,
          ),
        ),
        title: clientAsync.when(
          data: (client) => Text(
            client?.nombre ?? 'Cliente desconocido',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          loading: () => const Text('...'),
          error: (_, __) => const Text('Error'),
        ),
        subtitle: Row(
          children: [
            Flexible(
              child: Text(
                '${DateFormatter.display(gig.fecha)}${gig.cachet != null ? ' · ${CurrencyFormatter.format(gig.cachet!)}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 11,
                  color: badgeTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            FacturableBadge(facturable: gig.facturable),
          ],
        ),
      ),
    );
  }
}

// ==================== OVERDUE BANNER ====================

class _OverdueBanner extends StatelessWidget {
  final OverdueAlert alert;
  const _OverdueBanner({required this.alert});

  @override
  Widget build(BuildContext context) {
    final isRed = alert.hasOver30Days;
    final bgColor = isRed ? AppColors.errorBg : AppColors.warningBg;
    final borderColor = isRed ? AppColors.error : AppColors.warning;
    final iconColor = isRed ? AppColors.error : AppColors.warning;
    final n = alert.invoices.length;

    return GestureDetector(
      onTap: () => context.go('/finanzas'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: borderColor, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tienes $n factura${n == 1 ? '' : 's'} pendiente${n == 1 ? '' : 's'} desde hace más de 7 días',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: borderColor,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...alert.invoices.map(
              (oi) => Padding(
                padding: const EdgeInsets.only(left: 28, top: 2),
                child: Text(
                  '· ${oi.clientName} — ${CurrencyFormatter.format(oi.invoice.total)} — ${oi.daysSinceSent} días',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== ACTIVITY STREAK ====================

class _ActivityCard extends StatelessWidget {
  final ActivityStreak activity;
  const _ActivityCard({required this.activity});

  @override
  Widget build(BuildContext context) {
    if (activity.daysSinceLastGig < 0) return const SizedBox.shrink();

    final days = activity.daysSinceLastGig;
    String emoji;
    String text;
    Color color;

    if (days <= 2) {
      emoji = '🟢';
      text = days == 0
          ? 'Al día — último bolo registrado hoy'
          : 'Al día — último bolo hace $days día${days == 1 ? '' : 's'}';
      color = AppColors.success;
    } else if (days <= 7) {
      emoji = '🟡';
      text = '$days días sin registrar un bolo';
      color = AppColors.warning;
    } else {
      emoji = '🔴';
      text = 'Llevas $days días sin actividad';
      color = AppColors.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
