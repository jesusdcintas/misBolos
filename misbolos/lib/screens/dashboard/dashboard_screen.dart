import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/client.dart';
import '../../models/gig.dart';
import '../../providers/client_provider.dart';
import '../../providers/financial_summary_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/stats_provider.dart';
import '../../widgets/common/dismissible_alert_banner.dart';
import '../../widgets/common/dj_refresh_indicator.dart';
import '../../widgets/common/expandable_fab.dart';
import '../../widgets/common/facturable_badge.dart';
import '../../widgets/common/skeleton_loading.dart';
import '../../widgets/dashboard/income_period_card.dart';
import '../../widgets/dashboard/pending_invoices_card.dart';
import '../../widgets/dashboard/period_selector.dart';
import '../../widgets/dashboard/taxes_period_card.dart';
import 'package:go_router/go_router.dart';

/// Ancho a partir del cual las secciones se reparten en dos columnas. Es el
/// mismo corte que usa la pantalla de Ajustes.
const double _anchoDosColumnas = 700;

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(dashboardPeriodProvider);
    final statsAsync = ref.watch(periodDashboardStatsProvider(period));
    final fiscalAsync = ref.watch(financialSummaryProvider(period));
    final upcomingAsync = ref.watch(upcomingGigsProvider);
    final pendingAsync = ref.watch(pendingInvoicesInPeriodProvider(period));
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
          ref.invalidate(financialSummaryProvider(period));
          ref.invalidate(upcomingGigsProvider);
          ref.invalidate(pendingInvoicesInPeriodProvider(period));
          ref.invalidate(overdueInvoicesProvider);
          ref.invalidate(activityStreakProvider);
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final dosColumnas = constraints.maxWidth >= _anchoDosColumnas;

            final ingresos = statsAsync.when(
              data: (stats) => IncomePeriodCard(stats: stats, period: period),
              loading: () => const DashboardSkeleton(),
              error: (e, _) => Text('Error: $e'),
            );

            final impuestos = fiscalAsync.when(
              data: (summary) =>
                  TaxesPeriodCard(summary: summary, period: period),
              loading: () => const DashboardSkeleton(),
              error: (e, _) => Text('Error: $e'),
            );

            final proximos = upcomingAsync.when(
              data: (upcoming) => _UpcomingGigs(upcoming: upcoming),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            );

            final pendientes = pendingAsync.when(
              data: (lista) => PendingInvoicesCard(pendientes: lista),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            );

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const PeriodSelector(),
                const SizedBox(height: 16),

                // Aviso de impagos: es global, no sigue el periodo.
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

                _DosColumnas(
                  activo: dosColumnas,
                  izquierda: ingresos,
                  derecha: impuestos,
                ),
                const SizedBox(height: 24),

                _DosColumnas(
                  activo: dosColumnas,
                  izquierda: proximos,
                  derecha: pendientes,
                ),
                const SizedBox(height: 24),

                OutlinedButton.icon(
                  onPressed: () => context.push('/stats'),
                  icon: const Icon(Icons.bar_chart, size: 18),
                  label: const Text('Ver todas las métricas'),
                ),
                const SizedBox(height: 16),

                activityAsync.when(
                  data: (activity) => _ActivityCard(activity: activity),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                const SizedBox(height: 80),
              ],
            );
          },
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
            label: 'Nuevo gasto o inversión',
            color: AppColors.warning,
            onTap: (ctx) => ctx.push('/expense/new'),
          ),
        ],
      ),
    );
  }
}

/// Dos secciones en fila cuando hay sitio, y una debajo de otra si no.
class _DosColumnas extends StatelessWidget {
  final bool activo;
  final Widget izquierda;
  final Widget derecha;

  const _DosColumnas({
    required this.activo,
    required this.izquierda,
    required this.derecha,
  });

  @override
  Widget build(BuildContext context) {
    if (!activo) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [izquierda, const SizedBox(height: 24), derecha],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: izquierda),
        const SizedBox(width: 16),
        Expanded(child: derecha),
      ],
    );
  }
}

// ==================== PRÓXIMOS BOLOS ====================

class _UpcomingGigs extends StatelessWidget {
  final List<Gig> upcoming;

  const _UpcomingGigs({required this.upcoming});

  @override
  Widget build(BuildContext context) {
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
        Row(
          children: [
            Expanded(
              child: Text(
                'Próximos bolos',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: () => context.go('/calendar'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Agenda →'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (futureGigs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(20),
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
                  style: TextStyle(color: colors.textSecondary, fontSize: 14),
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

// ==================== GIG TILES ====================

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
            client?.displayName ?? 'Cliente desconocido',
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

/// Aviso compacto de facturas pendientes de más de 7 días, en una línea.
class _OverdueBanner extends StatelessWidget {
  final OverdueAlert alert;

  const _OverdueBanner({required this.alert});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isRed = alert.hasOver30Days;
    final acento = isRed ? colors.error : colors.warning;
    final fondo = isRed ? colors.errorBg : colors.warningBg;
    final n = alert.invoices.length;

    final String texto;
    if (n == 1) {
      final oi = alert.invoices.first;
      texto =
          '${oi.clientName} te debe '
          '${CurrencyFormatter.format(oi.invoice.total)} desde hace '
          '${oi.daysSinceSent} días';
    } else {
      texto = 'Tienes $n facturas pendientes desde hace más de 7 días';
    }

    return GestureDetector(
      onTap: () => context.go('/finanzas'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: acento, width: 3)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: acento, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texto,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: acento,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.textSecondary),
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
