import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../models/expense.dart';
import '../../providers/expenses_provider.dart';
import '../../widgets/common/empty_state.dart';

final _expenseCategoryFilterProvider =
    StateProvider<ExpenseCategory?>((ref) => null);
final _expenseMonthFilterProvider = StateProvider<int?>((ref) => null);
final _expenseYearFilterProvider =
    StateProvider<int?>((ref) => DateTime.now().year);

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider);
    final categoriaFilter = ref.watch(_expenseCategoryFilterProvider);
    final monthFilter = ref.watch(_expenseMonthFilterProvider);
    final yearFilter = ref.watch(_expenseYearFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gastos'),
        actions: [
          PopupMenuButton<ExpenseCategory?>(
            icon: Icon(
              Icons.filter_list,
              color: categoriaFilter != null ? AppColors.primary : null,
            ),
            tooltip: 'Filtrar por categoría',
            onSelected: (value) {
              ref.read(_expenseCategoryFilterProvider.notifier).state = value;
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: null,
                child: Text('Todas las categorías'),
              ),
              const PopupMenuDivider(),
              ...ExpenseCategory.values.map(
                (cat) => PopupMenuItem(
                  value: cat,
                  child: Text(cat.label),
                ),
              ),
            ],
          ),
        ],
      ),
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

          if (filtered.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              message: 'Sin gastos. Añade el primero con el botón +',
            );
          }

          final totalMes = filtered.fold(0.0, (s, e) => s + e.total);
          final ivaSoportado =
              filtered.where((e) => e.esDeducible).fold(0.0, (s, e) => s + e.ivaAmount * (e.porcentajeDeduccion / 100));

          return Column(
            children: [
              _ResumenBanner(total: totalMes, ivaSoportado: ivaSoportado),
              _FiltroMes(
                year: yearFilter,
                month: monthFilter,
                onChanged: (y, m) {
                  ref.read(_expenseYearFilterProvider.notifier).state = y;
                  ref.read(_expenseMonthFilterProvider.notifier).state = m;
                },
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _ExpenseCard(
                      expense: filtered[index],
                      onTap: () =>
                          context.push('/expense/${filtered[index].id}'),
                    );
                  },
                ),
              ),
            ],
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
            child: _Stat(
                label: 'Total gastos', value: fmt.format(total)),
          ),
          Container(
            width: 1,
            height: 32,
            color: AppColors.divider,
          ),
          Expanded(
            child: _Stat(
                label: 'IVA soportado', value: fmt.format(ivaSoportado)),
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
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
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
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
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
              onSelected: (_) => onChanged(year, null),
            );
          }
          final m = index;
          final selected = month == m;
          return FilterChip(
            label: Text(months[m - 1]),
            selected: selected,
            onSelected: (_) => onChanged(year, selected ? null : m),
          );
        },
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
