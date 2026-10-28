import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../providers/stats_provider.dart';

/// Selector de periodo (Mes / Trimestre / Año) y navegación entre periodos.
///
/// Escribe en [dashboardPeriodProvider], así que todas las pantallas que lo
/// usan comparten el mismo periodo.
class PeriodSelector extends ConsumerWidget {
  const PeriodSelector({super.key});

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
