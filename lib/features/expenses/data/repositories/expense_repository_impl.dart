import 'package:mi_finca_app/features/expenses/data/datasources/expense_local_datasource.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/expenses/domain/repositories/expense_repository.dart';
import 'package:mi_finca_app/features/sync/domain/repositories/sync_repository.dart';

class ExpenseRepositoryImpl implements ExpenseRepository {
  const ExpenseRepositoryImpl({
    required ExpenseLocalDataSource local,
    required ExpenseRemoteDataSource remote,
    TombstoneSyncRepository? sync,
  }) : _local = local,
       _remote = remote,
       _sync = sync;
  final ExpenseLocalDataSource _local;
  final ExpenseRemoteDataSource _remote;
  final TombstoneSyncRepository? _sync;

  @override
  Future<List<Expense>> getLocal() => _local.getAll();

  @override
  Future<List<Expense>> getAll() async {
    final items = await getLocal();
    if (items.isNotEmpty || await _local.hasStoredExpenses()) return items;
    try {
      await _downloadActive();
    } catch (_) {
      // Opening the app remains local-first, including a completely empty list.
    }
    return getLocal();
  }

  Future<void> _downloadActive() async {
    final owner = await _local.owner();
    if (owner == null || _remote.currentUserId != owner) {
      throw StateError('La sesión cambió.');
    }
    final snapshot = await _local.snapshot(owner);
    final items = await _remote.getAll();
    if (_remote.currentUserId != owner) throw StateError('La sesión cambió.');
    await _local.mergeActive(items, owner, snapshot);
  }

  @override
  Future<List<Expense>> refresh() async {
    final sync = _sync;
    if (sync == null) throw StateError('Actualización no disponible.');
    await sync.pullRemoteTombstones();
    await _downloadActive();
    return getLocal();
  }

  @override
  Future<void> save(Expense expense) => _local.save(expense);

  @override
  Future<void> deleteExpense(String expenseId) async {
    final owner = await _local.owner();
    final record = await _local.record(expenseId);
    if (owner == null ||
        record == null ||
        (record.ownerId != null && record.ownerId != owner) ||
        (_remote.currentUserId != null && _remote.currentUserId != owner)) {
      throw StateError('No se puede eliminar este gasto con esta cuenta.');
    }
    if (record.ownerId == null) {
      // DELETE A validates remote evidence and adopts only the same snapshot.
      // Never infer a legacy row's owner from the current login alone.
      try {
        if (!await (_sync?.verifyLegacyOwnership(
              'expenses',
              expenseId,
              owner,
            ) ??
            Future.value(false))) {
          throw const ExpenseOwnershipUnverified();
        }
      } catch (_) {
        throw const ExpenseOwnershipUnverified();
      }
    }
    // Returns after the durable local transaction, never after a network DELETE.
    await _local.markDeleted(expenseId, owner);
  }
}
