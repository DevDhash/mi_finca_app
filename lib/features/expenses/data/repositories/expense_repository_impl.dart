import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_local_datasource.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/expenses/domain/repositories/expense_repository.dart';

class ExpenseRepositoryImpl implements ExpenseRepository {
  const ExpenseRepositoryImpl({
    required ExpenseLocalDataSource local,
    required ExpenseRemoteDataSource remote,
  }) : _local = local,
       _remote = remote;

  final ExpenseLocalDataSource _local;
  final ExpenseRemoteDataSource _remote;

  @override
  Future<List<Expense>> getAll() async {
    final localItems = await _local.getAll();

    if (localItems.isNotEmpty) return localItems;

    try {
      final remoteItems = await _remote.getAll();

      for (final expense in remoteItems) {
        await _local.save(
          Expense(
            id: expense.id,
            category: expense.category,
            amount: expense.amount,
            date: expense.date,
            note: expense.note,
            updatedAt: expense.updatedAt,
            syncStatus: SyncStatus.synced,
          ),
          pending: false,
        );
      }

      return remoteItems;
    } catch (_) {
      return localItems;
    }
  }

  @override
  Future<void> save(Expense expense) async {
    await _local.save(expense);
  }
}
