import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../models/asset.dart';
import '../../models/expense.dart';
import '../../providers/assets_provider.dart';
import '../../providers/expenses_provider.dart';
import '../../providers/sync_provider.dart';
import '../../widgets/common/empty_state.dart';

enum _MovimientoSortOption { fechaDesc, fechaAsc, importeDesc, importeAsc }

final _movimientoYearFilterProvider = StateProvider<int?>(
  (ref) => DateTime.now().year,
);
final _movimientoMonthFilterProvider = StateProvider<int?>((ref) => null);
final _movimientoSortProvider = StateProvider<_MovimientoSortOption>(
  (ref) => _MovimientoSortOption.fechaDesc,
);

/// Lista unificada de "Gastos e Inversiones".
///
/// Los gastos ([Expense]) son el repositorio canónico y editable. Los assets
/// ([Asset]) son registros legacy que se muestran en modo solo-lectura.
class GastosInversionesScreen extends ConsumerStatefulWidget {
  const GastosInversionesScreen({super.key});

  @override
  ConsumerState<GastosInversionesScreen> createState() =>
      _GastosInversionesScreenState();
}

class _GastosInversionesScreenState
    extends ConsumerState<GastosInversionesScreen> {
  bool _entered = false;
  ExpensesNotifier? _expensesNotifier;
  AssetsNotifier? _assetsNotifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entered) return;
    _entered = true;
    _expensesNotifier = ref.read(expensesProvider.notifier);
    _assetsNotifier = ref.read(assetsProvider.notifier);
    Future.microtask(() {
      _expensesNotifier?.enterScreen();
      _assetsNotifier?.enterScreen();
    });
  }

  @override
  void dispose() {
    _expensesNotifier?.leaveScreen();
    _assetsNotifier?.leaveScreen();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    try {
      await ref.read(syncProvider.notifier).syncAll(reason: 'pull_to_refresh');
    } catch (_) {
      await ref.read(expensesProvider.notifier).reloadLocal();
      await ref.read(assetsProvider.notifier).reloadLocal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesProvider);
    final assetsAsync = ref.watch(assetsProvider);
    final yearFilter = ref.watch(_movimientoYearFilterProvider);
    final monthFilter = ref.watch(_movimientoMonthFilterProvider);
    final sortOption = ref.watch(_movimientoSortProvider);

    final expenses = expensesAsync.valueOrNull ?? const <Expense>[];
    final assets = assetsAsync.valueOrNull ?? const <Asset>[];
    final isLoading = expensesAsync.isLoading && assetsAsync.isLoading;

    return Scaffold(
      body: Builder(
        builder: (context) {
          if (isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = _buildItems(expenses, assets);
          final filtered = _applyFilters(items, monthFilter, yearFilter);
          _sortItems(filtered, sortOption);

          final total = filtered.fold<double>(0.0, (s, i) => s + i.importe);

          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const _CompactHeader(title: 'Gastos e Inversiones'),
                _ResumenBanner(total: total, count: filtered.length),
                _MovimientoActions(
                  sortOption: sortOption,
                  onSortChanged: (value) {
                    ref.read(_movimientoSortProvider.notifier).state = value;
                  },
                ),
                _FiltroMes(
                  year: yearFilter,
                  month: monthFilter,
                  onChanged: (y, m) {
                    ref.read(_movimientoYearFilterProvider.notifier).state = y;
                    ref.read(_movimientoMonthFilterProvider.notifier).state = m;
                  },
                ),
                if (filtered.isEmpty)
                  const SizedBox(
                    height: 420,
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: 'Sin gastos ni inversiones para este filtro',
                    ),
                  )
                else
                  ...filtered.map(
                    (item) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _MovimientoCard(item: item),
                    ),
                  ),
                const SizedBox(height: 84),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/expense/new'),
        child: const Icon(Icons.add),
      ),
    );
  }

  List<_MovimientoItem> _buildItems(
    List<Expense> expenses,
    List<Asset> assets,
  ) {
    final items = <_MovimientoItem>[];
    for (final e in expenses) {
      items.add(
        _MovimientoItem(
          fecha: e.fecha,
          titulo: e.concepto,
          subtitulo: e.categoria.label,
          importe: e.total,
          icono: _expenseIcon(e.categoria),
          isInversion: false,
          route: e.id != null ? '/expense/${e.id}' : null,
        ),
      );
    }
    for (final a in assets) {
      items.add(
        _MovimientoItem(
          fecha: a.fechaCompra,
          titulo: a.descripcion,
          subtitulo: a.categoria.label,
          importe: a.importeTotal,
          icono: a.categoria.icono,
          isInversion: true,
          route: a.id != null ? '/asset/${a.id}' : null,
        ),
      );
    }
    return items;
  }

  List<_MovimientoItem> _applyFilters(
    List<_MovimientoItem> items,
    int? month,
    int? year,
  ) {
    return items.where((i) {
      if (year != null && i.fecha.year != year) return false;
      if (month != null && i.fecha.month != month) return false;
      return true;
    }).toList();
  }

  void _sortItems(List<_MovimientoItem> items, _MovimientoSortOption option) {
    items.sort((a, b) {
      switch (option) {
        case _MovimientoSortOption.fechaDesc:
          return b.fecha.compareTo(a.fecha);
        case _MovimientoSortOption.fechaAsc:
          return a.fecha.compareTo(b.fecha);
        case _MovimientoSortOption.importeDesc:
          return b.importe.compareTo(a.importe);
        case _MovimientoSortOption.importeAsc:
          return a.importe.compareTo(b.importe);
      }
    });
  }

  IconData _expenseIcon(ExpenseCategory cat) {
    switch (cat) {
      case ExpenseCategory.combustible:
        return Icons.local_gas_station_outlined;
      case ExpenseCategory.transporte:
        return Icons.directions_car_outlined;
      case ExpenseCategory.equipo:
        return Icons.speaker_outlined;
      case ExpenseCategory.software:
        return Icons.computer_outlined;
      case ExpenseCategory.dietas:
        return Icons.restaurant_outlined;
      case ExpenseCategory.publicidad:
        return Icons.campaign_outlined;
      case ExpenseCategory.formacion:
        return Icons.school_outlined;
      case ExpenseCategory.otros:
        return Icons.receipt_outlined;
    }
  }
}

class _MovimientoItem {
  final DateTime fecha;
  final String titulo;
  final String subtitulo;
  final double importe;
  final IconData icono;
  final bool isInversion;
  final String? route;

  const _MovimientoItem({
    required this.fecha,
    required this.titulo,
    required this.subtitulo,
    required this.importe,
    required this.icono,
    required this.isInversion,
    required this.route,
  });
}

class _CompactHeader extends StatelessWidget {
  final String title;

  const _CompactHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border, width: 0.6)),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

class _ResumenBanner extends StatelessWidget {
  final double total;
  final int count;

  const _ResumenBanner({required this.total, required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(label: 'Total', value: fmt.format(total)),
          ),
          Container(width: 1, height: 32, color: colors.border),
          Expanded(
            child: _Stat(label: 'Movimientos', value: '$count'),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _MovimientoActions extends StatelessWidget {
  final _MovimientoSortOption sortOption;
  final ValueChanged<_MovimientoSortOption> onSortChanged;

  const _MovimientoActions({
    required this.sortOption,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: PopupMenuButton<_MovimientoSortOption>(
              onSelected: onSortChanged,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _MovimientoSortOption.fechaDesc,
                  child: Text('Fecha reciente'),
                ),
                PopupMenuItem(
                  value: _MovimientoSortOption.fechaAsc,
                  child: Text('Fecha antigua'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: _MovimientoSortOption.importeDesc,
                  child: Text('Importe mayor'),
                ),
                PopupMenuItem(
                  value: _MovimientoSortOption.importeAsc,
                  child: Text('Importe menor'),
                ),
              ],
              child: const _ActionPill(icon: Icons.sort, label: 'Ordenar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ActionPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = colors.textPrimary;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.noScaling),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltroMes extends StatelessWidget {
  final int? year;
  final int? month;
  final void Function(int? year, int? month) onChanged;

  const _FiltroMes({
    required this.year,
    required this.month,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;
    final months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: months.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          if (index == 0) {
            final selected = month == null;
            return FilterChip(
              label: const Text('Todo'),
              selected: selected,
              selectedColor: primary.withValues(alpha: 0.22),
              backgroundColor: colors.surfaceContainer,
              side: BorderSide(color: selected ? primary : colors.border),
              checkmarkColor: primary,
              labelStyle: TextStyle(
                color: selected ? primary : colors.textPrimary,
              ),
              onSelected: (_) => onChanged(year, null),
            );
          }
          final m = index;
          final selected = month == m;
          return FilterChip(
            label: Text(months[m - 1]),
            selected: selected,
            selectedColor: primary.withValues(alpha: 0.22),
            backgroundColor: colors.surfaceContainer,
            side: BorderSide(color: selected ? primary : colors.border),
            checkmarkColor: primary,
            labelStyle: TextStyle(
              color: selected ? primary : colors.textPrimary,
            ),
            onSelected: (_) => onChanged(year, selected ? null : m),
          );
        },
      ),
    );
  }
}

class _MovimientoCard extends StatelessWidget {
  final _MovimientoItem item;

  const _MovimientoCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    final dateFmt = DateFormat('d MMM', 'es_ES');
    final route = item.route;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: route == null ? null : () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.infoBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  item.icono,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.titulo,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.subtitulo}  ·  ${dateFmt.format(item.fecha)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fmt.format(item.importe),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (item.isInversion)
                    Text(
                      'Inversión',
                      style: TextStyle(fontSize: 10, color: colors.textMuted),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
