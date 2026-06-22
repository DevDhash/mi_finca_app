import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_local_datasource.dart';
import 'package:mi_finca_app/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:mi_finca_app/features/expenses/domain/repositories/expense_repository.dart';

final expenseLocalDataSourceProvider = Provider(
  (ref) => ExpenseLocalDataSource(ref.watch(databaseProvider)),
);
final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepositoryImpl(ref.watch(expenseLocalDataSourceProvider)),
);
final expenseViewModelProvider =
    AsyncNotifierProvider<ExpenseViewModel, List<Expense>>(
      ExpenseViewModel.new,
    );

final monthlyExpenseTotalProvider = Provider<double>((ref) {
  final expenses = ref.watch(expenseViewModelProvider).value ?? const [];
  final now = DateTime.now();
  return expenses
      .where((e) => e.date.year == now.year && e.date.month == now.month)
      .fold(0, (sum, e) => sum + e.amount);
});

class ExpenseViewModel extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() =>
      ref.watch(expenseRepositoryProvider).getAll();
  Future<void> save(Expense expense) async {
    await ref.read(expenseRepositoryProvider).save(expense);
    state = AsyncData([expense, ...state.requireValue]);
  }

  Future<void> reload() async =>
      state = AsyncData(await ref.read(expenseRepositoryProvider).getAll());
}
