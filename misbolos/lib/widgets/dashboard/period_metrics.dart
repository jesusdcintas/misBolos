import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../providers/stats_provider.dart';
import 'period_selector.dart';
import 'summary_card.dart';
import '../../core/theme/app_theme_colors.dart';

/// Grupo de métricas que muestra una sección.
enum PeriodMetricsScope { oficial, privado, global }

/// Sección «Métricas del periodo».
///
/// Son las tarjetas que antes estaban en Inicio, con sus mismos cálculos e
/// iconos de información. Lleva el selector de periodo compartido, así que el
/// periodo es el mismo que el de Inicio en ambos sentidos.
class PeriodMetricsSection extends ConsumerWidget {
  final PeriodMetricsScope scope;

  const PeriodMetricsSection({super.key, required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(dashboardPeriodProvider);
    final statsAsync = ref.watch(periodDashboardStatsProvider(period));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Métricas del periodo',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const PeriodSelector(),
        const SizedBox(height: 16),
        statsAsync.when(
          data: (stats) => switch (scope) {
            PeriodMetricsScope.oficial => _MetricasOficial(
              stats: stats,
              period: period,
            ),
            PeriodMetricsScope.privado => _MetricasPrivado(stats: stats),
            PeriodMetricsScope.global => _MetricasGlobal(stats: stats),
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
        ),
      ],
    );
  }
}

class _MetricasOficial extends StatelessWidget {
  final PeriodDashboardStats stats;
  final DashboardPeriod period;

  const _MetricasOficial({required this.stats, required this.period});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              color: context.colors.success,
              icon: Icons.check_circle_outline,
              showChevron: true,
              onTap: () => context.push('/financial'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '(facturas: ${CurrencyFormatter.format(stats.cobradoFacturas)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.textSecondary,
                    ),
                  ),
                  Text(
                    ' + histórico: ${CurrencyFormatter.format(stats.cobradoHistorico)})',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.textSecondary,
                    ),
                  ),
                  _buildComparison(context, 
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
              color: context.colors.warning,
              icon: Icons.schedule,
              showChevron: true,
              onTap: () => context.go('/finanzas'),
              subtitle: Text(
                '(${stats.pendienteCount} factura${stats.pendienteCount == 1 ? '' : 's'} emitida${stats.pendienteCount == 1 ? '' : 's'} sin cobrar)',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textSecondary,
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
          color: context.colors.accentSoft,
          icon: Icons.event_available,
          backgroundColor: context.colors.accentSoftBg,
          subtitle: Text(
            '(${stats.previstoConfirmadoCount} bolo${stats.previstoConfirmadoCount == 1 ? '' : 's'} confirmado${stats.previstoConfirmadoCount == 1 ? '' : 's'} en agenda\n aún no realizado${stats.previstoConfirmadoCount == 1 ? '' : 's'} ni facturado${stats.previstoConfirmadoCount == 1 ? '' : 's'})',
            style: TextStyle(fontSize: 11, color: context.colors.textSecondary),
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
              color: context.colors.success,
              icon: Icons.account_balance,
              subtitle: Text(
                '(cobrado oficial ${CurrencyFormatter.format(stats.cobradoOficial)}\n + pendiente de cobro ${CurrencyFormatter.format(stats.pendiente)})',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textSecondary,
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
              color: context.colors.draft,
              icon: Icons.trending_up,
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '(acumulado ${CurrencyFormatter.format(stats.acumulado)}'
                    '\n + confirmado ${CurrencyFormatter.format(stats.previstoConfirmado)}'
                    '\n + borrador ${CurrencyFormatter.format(stats.previstoBorrador)})',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.textSecondary,
                    ),
                  ),
                  Text(
                    '· proyección',
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: context.colors.textSecondary,
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
            color: context.colors.accentSoft,
            icon: Icons.description_outlined,
            showChevron: true,
            onTap: () => context.push('/stats'),
            subtitle: stats.ivaHistoricoEstimado > 0
                ? Text(
                    '(facturas: ${CurrencyFormatter.format(stats.ivaAcumulado)} + est. histórico: ${CurrencyFormatter.format(stats.ivaHistoricoEstimado)})',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.textSecondary,
                    ),
                  )
                : null,
          ),
        ),

      const SizedBox(height: 20),
      ],
    );
  }
}

class _MetricasPrivado extends StatelessWidget {
  final PeriodDashboardStats stats;

  const _MetricasPrivado({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
      // Eventos privados
      Text(
        AppStrings.ingresosEnB,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: context.colors.purple,
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
              color: context.colors.purple,
              icon: Icons.money_off_outlined,
              showChevron: true,
              onTap: () => context.push('/financial'),
              subtitle: Text(
                '(${stats.numBolosB} evento${stats.numBolosB == 1 ? '' : 's'} privado${stats.numBolosB == 1 ? '' : 's'})',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textSecondary,
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
              color: context.colors.purple,
              icon: Icons.hourglass_empty_outlined,
              showChevron: true,
              onTap: () => context.push('/financial'),
              subtitle: Text(
                '(${stats.pendienteEnBCount} evento${stats.pendienteEnBCount == 1 ? '' : 's'} privado${stats.pendienteEnBCount == 1 ? '' : 's'} realizado${stats.pendienteEnBCount == 1 ? '' : 's'} sin cobrar)',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textSecondary,
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
              color: context.colors.purple,
              icon: Icons.account_balance,
              subtitle: Text(
                '(${stats.previstoEnBCount} evento${stats.previstoEnBCount == 1 ? '' : 's'} privado${stats.previstoEnBCount == 1 ? '' : 's'} cerrado${stats.previstoEnBCount == 1 ? '' : 's'})',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textSecondary,
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
              color: context.colors.purple,
              icon: Icons.trending_up,
              subtitle: Text(
                '(cobrado ${CurrencyFormatter.format(stats.cobradoEnB)}\n + pendiente ${CurrencyFormatter.format(stats.pendienteEnB)}\n + confirmado ${CurrencyFormatter.format(stats.previstoEnB)})',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textSecondary,
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
      ],
    );
  }
}

class _MetricasGlobal extends StatelessWidget {
  final PeriodDashboardStats stats;

  const _MetricasGlobal({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              color: context.colors.success,
              icon: Icons.check_circle_outline,
              subtitle: Text(
                '(oficial ${CurrencyFormatter.format(stats.cobradoOficial)}\n + privado ${CurrencyFormatter.format(stats.cobradoEnB)})',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textSecondary,
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
              color: context.colors.warning,
              icon: Icons.schedule,
              subtitle: Text(
                '(acumulado ${CurrencyFormatter.format(stats.acumuladoTotal)}'
                '\n + confirmado ${CurrencyFormatter.format(stats.previstoConfirmado + stats.previstoEnB)}'
                '\n + borrador ${CurrencyFormatter.format(stats.previstoBorrador)})',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textSecondary,
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
          color: context.colors.accentSoft,
          icon: Icons.event_available,
          backgroundColor: context.colors.accentSoftBg,
          subtitle: Text(
            '(oficial ${CurrencyFormatter.format(stats.previsto)} + B ${CurrencyFormatter.format(stats.previstoEnB)})',
            style: TextStyle(fontSize: 11, color: context.colors.textSecondary),
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
              color: context.colors.success,
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
              color: context.colors.draft,
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
        color: context.colors.accentSoft,
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
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildComparison(
  BuildContext context,
  double current,
  double? previous,
  String? label,
) {
  if (previous == null || label == null) return const SizedBox.shrink();

  if (previous == 0 && current == 0) {
    return Text(
      '= igual que $label',
      style: TextStyle(fontSize: 11, color: context.colors.textSecondary),
    );
  }
  if (previous == 0) {
    return Text(
      '↑ nuevo vs $label',
      style: TextStyle(fontSize: 11, color: context.colors.success),
    );
  }

  final pct = ((current - previous) / previous * 100).round();
  if (pct == 0) {
    return Text(
      '= igual que $label',
      style: TextStyle(fontSize: 11, color: context.colors.textSecondary),
    );
  }

  final isUp = pct > 0;
  return Text(
    '${isUp ? '↑' : '↓'} ${isUp ? '+' : ''}$pct% vs $label',
    style: TextStyle(
      fontSize: 11,
      color: isUp ? context.colors.success : context.colors.error,
    ),
  );
}
