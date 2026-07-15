import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_local_datasource.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:mi_finca_app/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/expenses/domain/repositories/expense_repository.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final expenseLocalDataSourceProvider = Provider(
  (ref) => ExpenseLocalDataSource(ref.watch(databaseProvider)),
);

final expenseRemoteDataSourceProvider = Provider(
  (ref) => ExpenseRemoteDataSource(Supabase.instance.client),
);

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepositoryImpl(
    local: ref.watch(expenseLocalDataSourceProvider),
    remote: ref.watch(expenseRemoteDataSourceProvider),
  ),
);

final expenseViewModelProvider =
    AsyncNotifierProvider<ExpenseViewModel, List<Expense>>(
      ExpenseViewModel.new,
    );

final monthlyExpenseTotalProvider = Provider<double>((ref) {
  final expenses = ref.watch(expenseViewModelProvider).value ?? const [];
  final now = DateTime.now();

  return expenses
      .where(
        (expense) =>
            expense.date.year == now.year && expense.date.month == now.month,
      )
      .fold(0, (sum, expense) => sum + expense.amount);
});

class ExpenseViewModel extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() {
    return ref.watch(expenseRepositoryProvider).getAll();
  }

  Future<void> save(Expense expense) async {
    await ref.read(expenseRepositoryProvider).save(expense);

    final items = [...state.requireValue];
    final index = items.indexWhere((item) => item.id == expense.id);

    if (index < 0) {
      items.insert(0, expense);
    } else {
      items[index] = expense;
    }

    state = AsyncData(items);

    unawaited(ref.read(syncViewModelProvider.notifier).syncPendingIfOnline());
  }

  Future<void> reload() async {
    state = AsyncData(await ref.read(expenseRepositoryProvider).getAll());
  }
}
