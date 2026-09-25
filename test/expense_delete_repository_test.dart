import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_local_datasource.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:mi_finca_app/features/expenses/data/models/expense_model.dart';
import 'package:mi_finca_app/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/expenses/domain/repositories/expense_repository.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Expense expense(String id, {double amount = 20}) => Expense(
  id: id,
  category: 'Alimento',
  amount: amount,
  date: DateTime.now(),
  note: id,
  updatedAt: DateTime.now(),
);

class ExpenseTransport implements DeletionRemoteDataSource {
  @override
  String? currentUserId = 'owner';
  bool offline = true;
  bool lostReply = false;
  bool legacyVerified = false;
  final ledger = <String, RemoteTombstone>{};
  final deletes = <PendingRecord>[];
  Future<void> Function()? beforeDelete;
  @override
  Future<bool> verifyLegacyOwner(PendingRecord record, String ownerId) async {
    if (offline) throw const SocketException('offline');
    return legacyVerified;
  }

  @override
  Future<void> pushRecord(PendingRecord record) async {
    if (offline) throw const SocketException('offline');
    if (ledger.containsKey(record.id)) throw StateError('terminal');
  }

  @override
  Future<RemoteTombstone> softDelete(PendingRecord record) async {
    deletes.add(record);
    if (offline) throw const SocketException('offline');
    await beforeDelete?.call();
    final result = ledger.putIfAbsent(
      record.id,
      () => RemoteTombstone(
        collection: record.collection,
        id: record.id,
        ownerId: record.ownerId!,
        operationId: record.operationId!,
        deletedAt: DateTime.utc(2030),
      ),
    );
    if (lostReply) throw const SocketException('lost reply');
    return result;
  }

  @override
  Future<List<RemoteTombstone>> fetchTombstones(String ownerId) async {
    if (offline || lostReply) throw const SocketException('offline');
    return ledger.values.where((e) => e.ownerId == ownerId).toList();
  }
}

class RemoteExpenses extends ExpenseRemoteDataSource {
  RemoteExpenses() : super(SupabaseClient('https://example.test', 'test'));
  String? owner = 'owner';
  List<Expense> items = [];
  Future<void> Function()? beforeRead;
  bool fail = false;
  @override
  String? get currentUserId => owner;
  @override
  Future<List<Expense>> getAll() async {
    final snapshot = List<Expense>.of(items);
    await beforeRead?.call();
    if (fail) throw const SocketException('offline');
    return snapshot;
  }
}

void main() {
  late Directory directory;
  late AppDatabase db;
  late ExpenseTransport transport;
  late RemoteExpenses remote;
  late ExpenseRepositoryImpl repository;
  late SyncRepositoryImpl sync;
  void connect() {
    db = AppDatabase(NativeDatabase(File('${directory.path}/store.sqlite')));
    sync = SyncRepositoryImpl(SyncLocalDataSource(db), transport);
    repository = ExpenseRepositoryImpl(
      local: ExpenseLocalDataSource(db),
      remote: remote,
      sync: sync,
    );
  }

  Future<PendingRecord> record([String id = 'one']) async =>
      (await db.readRecord('expenses', id, includeDeleted: true))!;
  RemoteTombstone tombstone(String id) => RemoteTombstone(
    collection: 'expenses',
    id: id,
    ownerId: 'owner',
    operationId: 'server-operation',
    deletedAt: DateTime.utc(2030),
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('delete-b');
    transport = ExpenseTransport();
    remote = RemoteExpenses();
    connect();
    await db.writeSetting('session', jsonEncode({'id': 'owner'}));
    await repository.save(expense('one'));
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'offline delete persists tombstone and immediately hides expense without network',
    () async {
      await repository.deleteExpense('one');
      expect((await record()).operation, 'delete');
      expect((await record()).ownerId, 'owner');
      expect(await repository.getLocal(), isEmpty);
      expect(await db.readRecords('expenses'), isEmpty);
      expect(await db.pendingCount(), 1);
      expect(transport.deletes, isEmpty);
    },
  );
  test(
    'restart offline retains DELETE and reconnect acknowledges without removing tombstone',
    () async {
      await repository.deleteExpense('one');
      final original = await record();
      await db.close();
      connect();
      expect((await record()).operationId, original.operationId);
      remote.beforeRead = () async =>
          fail('Opening an all-deleted local list must not wait for network');
      expect(await repository.getAll(), isEmpty);
      expect(await db.pendingCount(), 1);
      transport.offline = false;
      await sync.pushPendingChanges();
      expect(transport.deletes.single.collection, 'expenses');
      expect(await db.pendingCount(), 0);
      expect((await record()).isDeleted, true);
      expect(
        SyncMetadata.read((await record()).payload)['deletedAt'],
        DateTime.utc(2030).toIso8601String(),
      );
    },
  );
  test(
    'network failure retains pending; lost response retries same operation idempotently',
    () async {
      await repository.deleteExpense('one');
      await sync.pushPendingChanges();
      expect(await db.pendingCount(), 1);
      transport.offline = false;
      transport.lostReply = true;
      await sync.pushPendingChanges();
      final original = transport.ledger['one']!;
      expect(await db.pendingCount(), 1);
      transport.lostReply = false;
      await sync.pushPendingChanges();
      expect(await db.pendingCount(), 0);
      expect(transport.ledger, hasLength(1));
      expect(transport.deletes.map((e) => e.operationId).toSet(), {
        original.operationId,
      });
    },
  );
  test(
    'duplicate deletion is idempotent and two distinct deletes stay independent',
    () async {
      await repository.save(expense('two'));
      await Future.wait([
        repository.deleteExpense('one'),
        repository.deleteExpense('one'),
      ]);
      final first = await record();
      await repository.deleteExpense('two');
      expect((await record()).payload, first.payload);
      expect((await record('two')).operationId, isNot(first.operationId));
      expect(await db.pendingCount(), 2);
      transport.offline = false;
      await sync.pushPendingChanges();
      expect(transport.ledger, hasLength(2));
      expect(await db.pendingCount(), 0);
    },
  );
  for (final pending in [true, false]) {
    test(
      'refresh consumes remote tombstone over local pending=$pending',
      () async {
        transport.offline = false;
        if (!pending) await sync.pushPendingChanges();
        transport.ledger['one'] = tombstone('one');
        remote.items = [expense('one')]; // Deliberately stale active response.
        expect(await repository.refresh(), isEmpty);
        expect((await record()).isDeleted, true);
        expect(await db.pendingCount(), 0);
        if (pending) {
          expect(
            SyncMetadata.read((await record()).payload)['conflict'],
            'remote_delete_wins',
          );
        }
      },
    );
  }
  test('local pending DELETE defeats remote active refresh', () async {
    await repository.deleteExpense('one');
    transport.offline = false;
    remote.items = [expense('one')];
    expect(await repository.refresh(), isEmpty);
    expect(await db.pendingCount(), 1);
  });
  test('empty remote response never deletes local expense', () async {
    transport.offline = false;
    await sync.pushPendingChanges();
    remote.items = [];
    expect(await repository.refresh(), hasLength(1));
    expect((await record()).isDeleted, false);
  });
  test(
    'wrong local or SDK account cannot delete or process pending operation',
    () async {
      remote.owner = 'other';
      await expectLater(repository.deleteExpense('one'), throwsStateError);
      remote.owner = 'owner';
      await repository.deleteExpense('one');
      await db.writeSetting('session', jsonEncode({'id': 'other'}));
      transport.currentUserId = 'other';
      transport.offline = false;
      await sync.pushPendingChanges();
      expect(transport.deletes, isEmpty);
      expect(await db.pendingCount(), 1);
    },
  );
  test('logout remains blocked by expense DELETE pending', () async {
    await repository.deleteExpense('one');
    await expectLater(
      db.beginSessionClose(),
      throwsA(isA<PendingSessionChanges>()),
    );
    expect(await db.pendingCount(), 1);
  });
  test('already confirmed remote DELETE is safe to repeat locally', () async {
    transport.offline = false;
    transport.ledger['one'] = tombstone('one');
    await repository.refresh();
    final original = await record();
    await repository.deleteExpense('one');
    expect((await record()).payload, original.payload);
    expect(await db.pendingCount(), 0);
  });
  test(
    'late active refresh cannot undo deletion made during download',
    () async {
      transport.offline = false;
      await sync.pushPendingChanges();
      remote.items = [expense('one')];
      remote.beforeRead = () => repository.deleteExpense('one');
      expect(await repository.refresh(), isEmpty);
      expect(await db.pendingCount(), 1);
    },
  );
  test(
    'legacy owner is not inferred offline but can be verified through DELETE A',
    () async {
      final payload = ExpenseModel.toJson(expense('legacy'));
      await db.customStatement('INSERT INTO records VALUES (?, ?, ?, ?, ?)', [
        'expenses',
        'legacy',
        jsonEncode(payload),
        0,
        0,
      ]);
      await expectLater(
        repository.deleteExpense('legacy'),
        throwsA(isA<ExpenseOwnershipUnverified>()),
      );
      expect((await record('legacy')).ownerId, isNull);
      transport.offline = false;
      transport.legacyVerified = true;
      await repository.deleteExpense('legacy');
      expect((await record('legacy')).ownerId, 'owner');
      expect((await record('legacy')).isDeleted, true);
    },
  );
  test(
    'create edit list and new authenticated download remain available',
    () async {
      await repository.save(expense('one', amount: 35));
      await repository.save(expense('two'));
      expect(
        (await repository.getAll()).firstWhere((e) => e.id == 'one').amount,
        35,
      );
      transport.offline = false;
      await sync.pushPendingChanges();
      remote.items = [expense('three')];
      expect(await repository.refresh(), hasLength(3));
      expect((await record('three')).ownerId, 'owner');
      await repository.deleteExpense('three');
      expect(await repository.getLocal(), hasLength(2));
    },
  );
  test(
    'another device pulls accepted deletion without assuming absence',
    () async {
      final otherDb = AppDatabase(NativeDatabase.memory());
      final otherSync = SyncRepositoryImpl(
        SyncLocalDataSource(otherDb),
        transport,
      );
      final other = ExpenseRepositoryImpl(
        local: ExpenseLocalDataSource(otherDb),
        remote: remote,
        sync: otherSync,
      );
      try {
        await otherDb.writeSetting('session', jsonEncode({'id': 'owner'}));
        await other.save(expense('one'));
        transport.offline = false;
        await otherSync.pushPendingChanges();
        await repository.deleteExpense('one');
        await sync.pushPendingChanges();
        expect(await other.getLocal(), hasLength(1));
        expect(await other.refresh(), isEmpty);
        expect(
          (await otherDb.readRecord(
            'expenses',
            'one',
            includeDeleted: true,
          ))!.isDeleted,
          true,
        );
      } finally {
        await otherDb.close();
      }
    },
  );
}
