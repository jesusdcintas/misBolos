import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/expense.dart';
import '../repositories/expense_repository.dart';

final expenseRepositoryProvider = Provider((ref) => ExpenseRepository.instance);

final expensesProvider = AsyncNotifierProvider<ExpensesNotifier, List<Expense>>(
  ExpensesNotifier.new,
);

class ExpensesNotifier extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() async {
    return ref.read(expenseRepositoryProvider).getAll();
  }

  Future<void> add(Expense expense) async {
    await ref.read(expenseRepositoryProvider).insert(expense);
    ref.invalidateSelf();
  }

  Future<void> updateExpense(Expense expense) async {
    await ref.read(expenseRepositoryProvider).update(expense);
    ref.invalidateSelf();
  }

  Future<void> remove(int id) async {
    await ref.read(expenseRepositoryProvider).delete(id);
    ref.invalidateSelf();
  }
}

final expenseByIdProvider = FutureProvider.family<Expense?, int>((ref, id) {
  return ref.read(expenseRepositoryProvider).getById(id);
});

final expensesByCategoriaProvider =
    FutureProvider.family<List<Expense>, ExpenseCategory>((ref, categoria) {
  return ref.read(expenseRepositoryProvider).getByCategoria(categoria);
});

final expensesByQuarterProvider =
    FutureProvider.family<List<Expense>, ({int year, int quarter})>(
        (ref, params) {
  final repo = ref.read(expenseRepositoryProvider);
  final startMonth = (params.quarter - 1) * 3 + 1;
  final from = DateTime(params.year, startMonth, 1);
  final to = DateTime(params.year, startMonth + 3, 0, 23, 59, 59);
  return repo.getByDateRange(from, to);
});

final gastosTrimestralProvider =
    FutureProvider.family<Map<String, double>, ({int year, int quarter})>(
        (ref, params) {
  return ref
      .read(expenseRepositoryProvider)
      .getTotalesPorCategoria(params.year, params.quarter);
});

final ivaDeducibleTrimestralProvider =
    FutureProvider.family<double, ({int year, int quarter})>((ref, params) {
  return ref
      .read(expenseRepositoryProvider)
      .getTotalIvaSoportadoTrimestre(params.year, params.quarter);
});
