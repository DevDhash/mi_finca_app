import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_local_datasource.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:mi_finca_app/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/expenses/domain/repositories/expense_repository.dart';
import 'package:mi_finca_app/features/sync/domain/repositories/sync_repository.dart';
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
    sync: ref.watch(syncRepositoryProvider) is TombstoneSyncRepository
        ? ref.watch(syncRepositoryProvider) as TombstoneSyncRepository
        : null,
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
  final _deletes = <String, Future<void>>{};
  int _changes = 0;
  Future<void>? _refresh;

  Future<void> deleteExpense(String id) =>
      _deletes[id] ??= _deleteExpense(id).whenComplete(() {
        _deletes.remove(id);
      });

  Future<void> _deleteExpense(String id) async {
    await ref.read(expenseRepositoryProvider).deleteExpense(id);
    if (!ref.mounted) return;
    _changes++;
    state = AsyncData((state.value ?? []).where((e) => e.id != id).toList());
    // Network failure must never turn an accepted local delete into a UI error.
    unawaited(_requestSync());
  }

  Future<void> _requestSync() async {
    try {
      await ref.read(syncViewModelProvider.notifier).syncPendingIfOnline();
    } catch (_) {
      // DELETE A/D keep the durable operation for the next retry.
    }
  }

  Future<void> refresh() => _refresh ??= _refreshExpenses().whenComplete(() {
    _refresh = null;
  });

  Future<void> _refreshExpenses() async {
    final repository = ref.read(expenseRepositoryProvider);
    try {
      await repository.refresh();
    } finally {
      // Also reflect a tombstone successfully pulled before an active GET failed.
      if (ref.mounted) await reload();
    }
  }

  @override
  Future<List<Expense>> build() {
    return ref.watch(expenseRepositoryProvider).getAll();
  }

  Future<void> save(Expense expense) async {
    final revision = _changes;
    await ref.read(expenseRepositoryProvider).save(expense);

    if (!ref.mounted) return;
    if (revision != _changes) {
      // A delete or another save completed while this save was in flight.
      await reload();
      if (ref.mounted) unawaited(_requestSync());
      return;
    }
    _changes++;
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
    final revision = _changes;
    final items = await ref.read(expenseRepositoryProvider).getLocal();
    if (ref.mounted && revision == _changes) state = AsyncData(items);
  }
}
