import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../models/expense.dart';
import '../../providers/expenses_provider.dart';
import '../../providers/sync_provider.dart';
import '../../widgets/common/empty_state.dart';

final _expenseCategoryFilterProvider = StateProvider<ExpenseCategory?>(
  (ref) => null,
);
final _expenseMonthFilterProvider = StateProvider<int?>((ref) => null);
final _expenseYearFilterProvider = StateProvider<int?>(
  (ref) => DateTime.now().year,
);

enum ExpenseSortOption { fechaDesc, fechaAsc, importeDesc, importeAsc }

final _expenseSortProvider = StateProvider<ExpenseSortOption>(
  (ref) => ExpenseSortOption.fechaDesc,
);

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  bool _entered = false;
  ExpensesNotifier? _expensesNotifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entered) return;
    _entered = true;
    _expensesNotifier = ref.read(expensesProvider.notifier);
    Future.microtask(() => _expensesNotifier?.enterScreen());
  }

  @override
  void dispose() {
    _expensesNotifier?.leaveScreen();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    try {
      await ref.read(syncProvider.notifier).syncAll(reason: 'pull_to_refresh');
    } catch (_) {
      await ref.read(expensesProvider.notifier).reloadLocal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesProvider);
    final categoriaFilter = ref.watch(_expenseCategoryFilterProvider);
    final monthFilter = ref.watch(_expenseMonthFilterProvider);
    final yearFilter = ref.watch(_expenseYearFilterProvider);
    final sortOption = ref.watch(_expenseSortProvider);

    return Scaffold(
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (expenses) {
          final filtered = _applyFilters(
            expenses,
            categoriaFilter,
            monthFilter,
            yearFilter,
          );
          _sortExpenses(filtered, sortOption);

          final totalMes = filtered.fold(0.0, (s, e) => s + e.total);
          final ivaSoportado = filtered
              .where((e) => e.esDeducible)
              .fold(
                0.0,
                (s, e) => s + e.ivaAmount * (e.porcentajeDeduccion / 100),
              );

          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const _CompactHeader(title: 'Gastos'),
                _ResumenBanner(total: totalMes, ivaSoportado: ivaSoportado),
                _ExpenseActions(
                  category: categoriaFilter,
                  sortOption: sortOption,
                  onCategoryChanged: (value) {
                    ref.read(_expenseCategoryFilterProvider.notifier).state =
                        value;
                  },
                  onSortChanged: (value) {
                    ref.read(_expenseSortProvider.notifier).state = value;
                  },
                ),
                _FiltroMes(
                  year: yearFilter,
                  month: monthFilter,
                  onChanged: (y, m) {
                    ref.read(_expenseYearFilterProvider.notifier).state = y;
                    ref.read(_expenseMonthFilterProvider.notifier).state = m;
                  },
                ),
                if (filtered.isEmpty)
                  const SizedBox(
                    height: 420,
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: 'Sin gastos para este filtro',
                    ),
                  )
                else
                  ...filtered.map(
                    (expense) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _ExpenseCard(
                        expense: expense,
                        onTap: () => context.push('/expense/${expense.id}'),
                      ),
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

  List<Expense> _applyFilters(
    List<Expense> expenses,
    ExpenseCategory? categoria,
    int? month,
    int? year,
  ) {
    return expenses.where((e) {
      if (categoria != null && e.categoria != categoria) return false;
      if (year != null && e.fecha.year != year) return false;
      if (month != null && e.fecha.month != month) return false;
      return true;
    }).toList();
  }

  void _sortExpenses(List<Expense> expenses, ExpenseSortOption option) {
    expenses.sort((a, b) {
      switch (option) {
        case ExpenseSortOption.fechaDesc:
          return b.fecha.compareTo(a.fecha);
        case ExpenseSortOption.fechaAsc:
          return a.fecha.compareTo(b.fecha);
        case ExpenseSortOption.importeDesc:
          return b.total.compareTo(a.total);
        case ExpenseSortOption.importeAsc:
          return a.total.compareTo(b.total);
      }
    });
  }
}

class _CompactHeader extends StatelessWidget {
  final String title;

  const _CompactHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _ExpenseActions extends StatelessWidget {
  final ExpenseCategory? category;
  final ExpenseSortOption sortOption;
  final ValueChanged<ExpenseCategory?> onCategoryChanged;
  final ValueChanged<ExpenseSortOption> onSortChanged;

  const _ExpenseActions({
    required this.category,
    required this.sortOption,
    required this.onCategoryChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: PopupMenuButton<ExpenseCategory?>(
              onSelected: onCategoryChanged,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: null,
                  child: Text('Todas las categorías'),
                ),
                const PopupMenuDivider(),
                ...ExpenseCategory.values.map(
                  (cat) => PopupMenuItem(value: cat, child: Text(cat.label)),
                ),
              ],
              child: _ActionPill(
                icon: Icons.filter_list,
                label: category?.label ?? 'Categoría',
                active: category != null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PopupMenuButton<ExpenseSortOption>(
              onSelected: onSortChanged,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: ExpenseSortOption.fechaDesc,
                  child: Text('Fecha reciente'),
                ),
                PopupMenuItem(
                  value: ExpenseSortOption.fechaAsc,
                  child: Text('Fecha antigua'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: ExpenseSortOption.importeDesc,
                  child: Text('Importe mayor'),
                ),
                PopupMenuItem(
                  value: ExpenseSortOption.importeAsc,
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

class _ResumenBanner extends StatelessWidget {
  final double total;
  final double ivaSoportado;

  const _ResumenBanner({required this.total, required this.ivaSoportado});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(label: 'Total gastos', value: fmt.format(total)),
          ),
          Container(width: 1, height: 32, color: AppColors.divider),
          Expanded(
            child: _Stat(
              label: 'IVA soportado',
              value: fmt.format(ivaSoportado),
            ),
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
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
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
              selectedColor: AppColors.primary,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
              onSelected: (_) => onChanged(year, null),
            );
          }
          final m = index;
          final selected = month == m;
          return FilterChip(
            label: Text(months[m - 1]),
            selected: selected,
            selectedColor: AppColors.primary,
            checkmarkColor: Colors.white,
            labelStyle: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
            ),
            onSelected: (_) => onChanged(year, selected ? null : m),
          );
        },
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _ActionPill({
    required this.icon,
    required this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textPrimary;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? AppColors.primary : AppColors.cardBorder,
        ),
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

class _ExpenseCard extends StatelessWidget {
  final Expense expense;
  final VoidCallback onTap;

  const _ExpenseCard({required this.expense, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    final dateFmt = DateFormat('d MMM', 'es_ES');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _categoryIcon(expense.categoria),
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.concepto,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${expense.categoria.label}  ·  ${dateFmt.format(expense.fecha)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
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
                    fmt.format(expense.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (!expense.esDeducible)
                    const Text(
                      'No deducible',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(ExpenseCategory cat) {
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
