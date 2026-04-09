import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../providers/stats_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../models/gig.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

final _selectedYearProvider = StateProvider<int>((ref) => DateTime.now().year);

// Toggle mensual/trimestral
enum ChartMode { mensual, trimestral }
final _chartModeProvider = StateProvider<ChartMode>((ref) => ChartMode.mensual);

// Tooltip state
final _tooltipDataProvider = StateProvider<PeriodTooltipData?>((ref) => null);

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.estadisticas),
          bottom: TabBar(
            tabs: const [
              Tab(text: AppStrings.oficial),
              Tab(text: AppStrings.enB),
              Tab(text: AppStrings.global),
            ],
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
          ),
        ),
        body: const TabBarView(
          children: [
            _OfficialTab(),
            _EnBTab(),
            _GlobalTab(),
          ],
        ),
      ),
    );
  }
}

class _OfficialTab extends ConsumerWidget {
  const _OfficialTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(_selectedYearProvider);
    final mode = ref.watch(_chartModeProvider);
    final statsAsync = ref.watch(yearlyStatsProvider(year));
    final quarterlyAsync = ref.watch(quarterlyIncomeProvider(year));
    final vatDetailAsync = ref.watch(yearlyVatDetailProvider(year));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _YearSelector(),
        const SizedBox(height: 12),
        const Center(child: _ChartModeToggle()),
        const SizedBox(height: 16),

        // Gráfico de barras
        if (mode == ChartMode.mensual)
          statsAsync.when(
            data: (months) => _buildMonthlyChart(ref, months, year, AppColors.accentGreen, (m) => m.oficial),
            loading: () => const SizedBox(height: 250, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('Error: $e'),
          )
        else
          quarterlyAsync.when(
            data: (quarters) => _buildQuarterlyChart(ref, quarters, year, (q) => q.oficial),
            loading: () => const SizedBox(height: 250, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('Error: $e'),
          ),

        // Tooltip
        const _TooltipCard(),
        const SizedBox(height: 20),

        // IVA por trimestres
        vatDetailAsync.when(
          data: (vatQuarters) => _IvaQuartersSection(vatQuarters: vatQuarters, year: year),
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
        ),

        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => _exportCsv(context, ref, oficialOnly: true),
          icon: const Icon(Icons.download),
          label: const Text('Exportar CSV oficial'),
        ),
      ],
    );
  }
}

class _EnBTab extends ConsumerWidget {
  const _EnBTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(_selectedYearProvider);
    final mode = ref.watch(_chartModeProvider);
    final statsAsync = ref.watch(yearlyStatsProvider(year));
    final quarterlyAsync = ref.watch(quarterlyIncomeProvider(year));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _YearSelector(),
        const SizedBox(height: 12),
        const Center(child: _ChartModeToggle()),
        const SizedBox(height: 16),

        if (mode == ChartMode.mensual)
          statsAsync.when(
            data: (months) => _buildMonthlyChart(ref, months, year, AppColors.accentPurple, (m) => m.enB),
            loading: () => const SizedBox(height: 250, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('Error: $e'),
          )
        else
          quarterlyAsync.when(
            data: (quarters) => _buildQuarterlyChart(ref, quarters, year, (q) => q.enB),
            loading: () => const SizedBox(height: 250, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('Error: $e'),
          ),

        const _TooltipCard(),
        const SizedBox(height: 16),
        const Card(
          color: Color(0xFFFFF3E0),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '⚠️ Estos datos se sincronizan cifrados en la nube, pero no generan facturas.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlobalTab extends ConsumerWidget {
  const _GlobalTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(_selectedYearProvider);
    final mode = ref.watch(_chartModeProvider);
    final statsAsync = ref.watch(yearlyStatsProvider(year));
    final quarterlyAsync = ref.watch(quarterlyIncomeProvider(year));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _YearSelector(),
        const SizedBox(height: 12),
        const Center(child: _ChartModeToggle()),
        const SizedBox(height: 16),
        statsAsync.when(
          data: (months) {
            double totalOficial = 0;
            double totalEnB = 0;
            for (final m in months) {
              totalOficial += m.oficial;
              totalEnB += m.enB;
            }
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Text('Total oficial'),
                              Text(CurrencyFormatter.format(totalOficial),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: AppColors.accentGreen,
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Text('Total en B'),
                              Text(CurrencyFormatter.format(totalEnB),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: AppColors.accentPurple,
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Card(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL GLOBAL',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          CurrencyFormatter.format(totalOficial + totalEnB),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (mode == ChartMode.mensual)
                  SizedBox(
                    height: 250,
                    child: BarChart(
                      BarChartData(
                        barTouchData: BarTouchData(
                          touchCallback: (event, response) {
                            if (event.isInterestedForInteractions &&
                                response?.spot != null) {
                              final idx = response!.spot!.touchedBarGroupIndex;
                              final m = months[idx];
                              ref.read(_tooltipDataProvider.notifier).state = PeriodTooltipData(
                                label: _monthLabel(m.month),
                                totalCobrado: m.total,
                                totalIva: 0,
                                numFacturas: 0,
                              );
                            }
                          },
                        ),
                        barGroups: months.map((m) {
                          return BarChartGroupData(x: m.month, barRods: [
                            BarChartRodData(
                              toY: m.total,
                              rodStackItems: [
                                BarChartRodStackItem(
                                    0, m.oficial, AppColors.accentGreen),
                                BarChartRodStackItem(m.oficial, m.total,
                                    AppColors.accentPurple),
                              ],
                              width: 16,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                              color: Colors.transparent,
                            ),
                          ]);
                        }).toList(),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) => Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(_monthLabel(v.toInt()),
                                    style: const TextStyle(fontSize: 10)),
                              ),
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 50,
                              getTitlesWidget: (v, _) => Text(
                                '${v.toInt()}€',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: const FlGridData(show: true),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  )
                else
                  quarterlyAsync.when(
                    data: (quarters) => _buildQuarterlyStackedChart(ref, quarters),
                    loading: () => const SizedBox(height: 250, child: Center(child: CircularProgressIndicator())),
                    error: (e, _) => Text('Error: $e'),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
        ),

        const _TooltipCard(),
      ],
    );
  }
}

class _YearSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(_selectedYearProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () =>
              ref.read(_selectedYearProvider.notifier).state = year - 1,
        ),
        Text('$year',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () =>
              ref.read(_selectedYearProvider.notifier).state = year + 1,
        ),
      ],
    );
  }
}

// ==================== CHART MODE TOGGLE ====================

class _ChartModeToggle extends ConsumerWidget {
  const _ChartModeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(_chartModeProvider);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleButton(
            label: 'Mensual',
            selected: mode == ChartMode.mensual,
            onTap: () => ref.read(_chartModeProvider.notifier).state = ChartMode.mensual,
          ),
          _ToggleButton(
            label: 'Trimestral',
            selected: mode == ChartMode.trimestral,
            onTap: () => ref.read(_chartModeProvider.notifier).state = ChartMode.trimestral,
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ==================== TOOLTIP CARD ====================

class _TooltipCard extends ConsumerWidget {
  const _TooltipCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_tooltipDataProvider);
    if (data == null) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, 20 * (1 - value)),
        child: Opacity(opacity: value, child: child),
      ),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  data.label.isNotEmpty
                      ? data.label[0].toUpperCase() + data.label.substring(1)
                      : '',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                GestureDetector(
                  onTap: () => ref.read(_tooltipDataProvider.notifier).state = null,
                  child: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _tooltipRow('Cobrado', CurrencyFormatter.format(data.totalCobrado), AppColors.success),
            _tooltipRow('IVA', CurrencyFormatter.format(data.totalIva), AppColors.warning),
            _tooltipRow('Facturas pagadas', '${data.numFacturas}', AppColors.primary),
          ],
        ),
      ),
    );
  }

  Widget _tooltipRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

// ==================== CHART BUILDERS ====================

Widget _buildMonthlyChart(
  WidgetRef ref,
  List<MonthlyIncome> months,
  int year,
  Color barColor,
  double Function(MonthlyIncome) getValue,
) {
  return SizedBox(
    height: 250,
    child: BarChart(
      BarChartData(
        barTouchData: BarTouchData(
          touchCallback: (event, response) async {
            if (event.isInterestedForInteractions && response?.spot != null) {
              final idx = response!.spot!.touchedBarGroupIndex;
              final m = months[idx];
              final data = await ref.read(
                monthTooltipProvider((year: year, month: m.month)).future,
              );
              ref.read(_tooltipDataProvider.notifier).state = data;
            }
          },
        ),
        barGroups: months.map((m) {
          return BarChartGroupData(x: m.month, barRods: [
            BarChartRodData(
              toY: getValue(m),
              color: barColor,
              width: 16,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ]);
        }).toList(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_monthLabel(v.toInt()),
                    style: const TextStyle(fontSize: 10)),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}€',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
      ),
    ),
  );
}

const _quarterLabels = ['', 'T1 · Ene-Mar', 'T2 · Abr-Jun', 'T3 · Jul-Sep', 'T4 · Oct-Dic'];

Widget _buildQuarterlyChart(
  WidgetRef ref,
  List<QuarterlyIncome> quarters,
  int year,
  double Function(QuarterlyIncome) getValue,
) {
  final now = DateTime.now();
  final currentQuarter = now.year == year ? ((now.month - 1) ~/ 3) + 1 : 0;

  return SizedBox(
    height: 250,
    child: BarChart(
      BarChartData(
        barTouchData: BarTouchData(
          touchCallback: (event, response) async {
            if (event.isInterestedForInteractions && response?.spot != null) {
              final idx = response!.spot!.touchedBarGroupIndex;
              final q = quarters[idx];
              final data = await ref.read(
                quarterTooltipProvider((year: year, quarter: q.quarter)).future,
              );
              ref.read(_tooltipDataProvider.notifier).state = data;
            }
          },
        ),
        barGroups: quarters.map((q) {
          Color color;
          if (q.quarter == currentQuarter) {
            color = AppColors.primary;
          } else if (q.quarter < currentQuarter || now.year > year) {
            color = AppColors.accentGreen;
          } else {
            color = AppColors.cardBorder;
          }

          return BarChartGroupData(x: q.quarter, barRods: [
            BarChartRodData(
              toY: getValue(q),
              color: color,
              width: 40,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ]);
        }).toList(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_quarterLabels[v.toInt().clamp(1, 4)],
                    style: const TextStyle(fontSize: 9)),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}€',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
      ),
    ),
  );
}

Widget _buildQuarterlyStackedChart(
  WidgetRef ref,
  List<QuarterlyIncome> quarters,
) {
  return SizedBox(
    height: 250,
    child: BarChart(
      BarChartData(
        barTouchData: BarTouchData(
          touchCallback: (event, response) {
            if (event.isInterestedForInteractions && response?.spot != null) {
              final idx = response!.spot!.touchedBarGroupIndex;
              final q = quarters[idx];
              ref.read(_tooltipDataProvider.notifier).state = PeriodTooltipData(
                label: 'T${q.quarter}',
                totalCobrado: q.total,
                totalIva: 0,
                numFacturas: 0,
              );
            }
          },
        ),
        barGroups: quarters.map((q) {
          return BarChartGroupData(x: q.quarter, barRods: [
            BarChartRodData(
              toY: q.total,
              rodStackItems: [
                BarChartRodStackItem(0, q.oficial, AppColors.accentGreen),
                BarChartRodStackItem(q.oficial, q.total, AppColors.accentPurple),
              ],
              width: 40,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              color: Colors.transparent,
            ),
          ]);
        }).toList(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_quarterLabels[v.toInt().clamp(1, 4)],
                    style: const TextStyle(fontSize: 9)),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}€',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
      ),
    ),
  );
}

// ==================== IVA QUARTERS SECTION ====================

const _quarterMonths = ['', 'Ene — Mar', 'Abr — Jun', 'Jul — Sep', 'Oct — Dic'];

class _IvaQuartersSection extends StatelessWidget {
  final List<QuarterVatDetail> vatQuarters;
  final int year;
  const _IvaQuartersSection({required this.vatQuarters, required this.year});

  @override
  Widget build(BuildContext context) {
    final totalIva = vatQuarters.fold(0.0, (s, q) => s + q.ivaTotal);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder, width: 0.5),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'IVA por trimestres · $year',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...vatQuarters.map((q) => _IvaQuarterTile(vat: q)),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL ANUAL IVA',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(CurrencyFormatter.format(totalIva),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.warning,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IvaQuarterTile extends StatefulWidget {
  final QuarterVatDetail vat;
  const _IvaQuarterTile({required this.vat});

  @override
  State<_IvaQuarterTile> createState() => _IvaQuarterTileState();
}

class _IvaQuarterTileState extends State<_IvaQuarterTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final vat = widget.vat;
    final declFormat = DateFormat('dd MMM yyyy', 'es');

    // Status badge
    Widget statusBadge;
    switch (vat.status) {
      case 'pendiente_declarar':
        statusBadge = _statusPill('Pendiente', AppColors.warningBg, AppColors.warning);
        break;
      case 'en_curso':
        statusBadge = _statusPill('En curso', AppColors.primaryLight, AppColors.primary);
        break;
      case 'proximo':
        statusBadge = _statusPill('Próximo', const Color(0xFFEEF1F7), AppColors.textSecondary);
        break;
      default:
        statusBadge = const SizedBox.shrink();
    }

    // Days color
    Color daysColor = AppColors.textSecondary;
    String daysLabel;
    if (vat.daysRemaining < 0) {
      daysLabel = 'vencido';
      daysColor = AppColors.error;
    } else if (vat.daysRemaining < 7) {
      daysLabel = '${vat.daysRemaining}d';
      daysColor = AppColors.error;
    } else if (vat.daysRemaining < 30) {
      daysLabel = '${vat.daysRemaining}d';
      daysColor = AppColors.warning;
    } else {
      daysLabel = '${vat.daysRemaining}d';
    }

    return Column(
      children: [
        InkWell(
          onTap: vat.invoices.isNotEmpty ? () => setState(() => _expanded = !_expanded) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('T${vat.quarter}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.primary,
                          )),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_quarterMonths[vat.quarter],
                          style: const TextStyle(fontSize: 13)),
                    ),
                    statusBadge,
                    const SizedBox(width: 8),
                    Text(CurrencyFormatter.format(vat.ivaTotal),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if (vat.invoices.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ],
                ),
                if (vat.status != 'proximo' || vat.ivaTotal > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 48),
                    child: Text(
                      'Límite: ${declFormat.format(vat.declarationDate)} — $daysLabel',
                      style: TextStyle(fontSize: 11, color: daysColor),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_expanded && vat.invoices.isNotEmpty)
          Container(
            color: const Color(0xFFF7F8FA),
            padding: const EdgeInsets.fromLTRB(32, 0, 16, 12),
            child: Column(
              children: [
                ...vat.invoices.map((inv) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 50,
                        child: Text('#${inv.numero}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                      Expanded(
                        child: Text(inv.clientName,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text(DateFormat('dd/MM', 'es').format(inv.fecha),
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 70,
                        child: Text(CurrencyFormatter.format(inv.base),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 60,
                        child: Text(CurrencyFormatter.format(inv.iva),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w500,
                            )),
                      ),
                    ],
                  ),
                )),
                const Divider(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text('Total: ',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    Text(CurrencyFormatter.format(vat.ivaTotal),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.warning,
                        )),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _statusPill(String label, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: text)),
    );
  }
}

String _monthLabel(int month) {
  const labels = [
    '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];
  return labels[month.clamp(1, 12)];
}

Future<void> _exportCsv(BuildContext context, WidgetRef ref,
    {bool oficialOnly = true}) async {
  try {
    final gigs = await ref.read(gigsProvider.future);
    final invoices = await ref.read(invoicesProvider.future);

    final rows = <List<dynamic>>[
      ['Fecha', 'Cliente', 'Caché', 'Facturable', 'Estado', 'Nº Factura'],
    ];

    for (final gig in gigs) {
      if (oficialOnly && !gig.facturable) continue;
      final inv = invoices.where((i) => i.gigId == gig.id).firstOrNull;
      rows.add([
        gig.fecha.toIso8601String().substring(0, 10),
        gig.clientId,
        gig.cachet ?? 0,
        gig.facturable ? 'Sí' : 'No',
        gig.status.label,
        inv?.numero ?? '',
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/misbolos_export.csv');
    await file.writeAsString(csv);

    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile(file.path)],
      sharePositionOrigin: box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 100, 100),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}
