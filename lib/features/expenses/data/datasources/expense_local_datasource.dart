import 'dart:convert';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/expenses/data/models/expense_model.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';

class ExpenseLocalDataSource {
  const ExpenseLocalDataSource(this._database);

  final AppDatabase _database;

  Future<List<Expense>> getAll() async => (await _database.readRecords(
    'expenses',
  )).map(ExpenseModel.fromJson).toList();

  Future<void> save(
    Expense expense, {
    bool pending = true,
    String? verifiedRemoteOwner,
  }) {
    return _database.putRecord(
      'expenses',
      expense.id,
      ExpenseModel.toJson(expense),
      expense.updatedAt,
      pending: pending,
      verifiedRemoteOwner: verifiedRemoteOwner,
    );
  }

  Future<bool> hasStoredExpenses() async => (await _database.readRecords(
    'expenses',
    includeDeleted: true,
  )).isNotEmpty;

  Future<String?> owner() => _database.localOwner();
  Future<PendingRecord?> record(String id) =>
      _database.readRecord('expenses', id, includeDeleted: true);
  Future<void> markDeleted(String id, String owner) =>
      _database.markDeleted('expenses', id, owner);

  Future<ExpenseRefreshSnapshot> snapshot(String owner) =>
      _database.runInTransaction(() async {
        await _database.requireOwner(owner);
        return ExpenseRefreshSnapshot(
          {
            for (final row in await _database.readRecords(
              'expenses',
              includeDeleted: true,
            ))
              row['id']! as String: row,
          },
          {
            for (final row in await _database.readPendingRecords())
              if (row.collection == 'expenses') row.id,
          },
        );
      });

  Future<void> mergeActive(
    List<Expense> expenses,
    String owner,
    ExpenseRefreshSnapshot snapshot,
  ) => _database.runInTransaction(() async {
    await _database.requireOwner(owner);
    for (final expense in expenses) {
      if (snapshot.pendingIds.contains(expense.id)) continue;
      final current = await record(expense.id);
      if (jsonEncode(current?.payload) !=
          jsonEncode(snapshot.payloads[expense.id])) {
        continue;
      }
      // DELETE A rejects resurrection and protects currently pending edits.
      await save(expense, pending: false, verifiedRemoteOwner: owner);
    }
  });

  Future<void> markSynced(String id) {
    return _database.markRecordSynced('expenses', id);
  }
}

class ExpenseRefreshSnapshot {
  const ExpenseRefreshSnapshot(this.payloads, this.pendingIds);
  final Map<String, Map<String, Object?>> payloads;
  final Set<String> pendingIds;
}
