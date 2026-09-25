import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';

class DeleteTransport implements DeletionRemoteDataSource {
  @override
  String? currentUserId = 'owner';
  int deletes = 0;
  int upserts = 0;
  bool verified = false;
  bool loseResponse = false;
  Future<void> Function()? beforeDelete;
  Future<void> Function()? beforeUpsert;
  final ledger = <String, RemoteTombstone>{};
  @override
  Future<bool> verifyLegacyOwner(PendingRecord r, String owner) async =>
      verified;
  @override
  Future<List<RemoteTombstone>> fetchTombstones(String owner) async =>
      ledger.values.where((t) => t.ownerId == owner).toList();
  @override
  Future<void> pushRecord(PendingRecord record) async {
    upserts++;
    await beforeUpsert?.call();
    if (ledger.containsKey(record.id)) throw StateError('SYNC_ENTITY_DELETED');
  }

  @override
  Future<RemoteTombstone> softDelete(PendingRecord record) async {
    deletes++;
    await beforeDelete?.call();
    final result = ledger.putIfAbsent(
      record.id,
      () => RemoteTombstone(
        collection: record.collection,
        id: record.id,
        ownerId: record.ownerId!,
        deletedAt: DateTime.utc(2026, 9, 25),
        operationId: record.operationId!,
      ),
    );
    if (loseResponse) throw const SocketException('lost reply');
    return result;
  }
}

void main() {
  late Directory directory;
  late AppDatabase db;
  late DeleteTransport remote;
  late SyncRepositoryImpl sync;
  void connect() {
    db = AppDatabase(NativeDatabase(File('${directory.path}/records.sqlite')));
    sync = SyncRepositoryImpl(SyncLocalDataSource(db), remote);
  }

  Future<void> create({String id = 'e1'}) => db.putRecord('expenses', id, {
    'id': id,
    'note': 'preserve me',
    'amount': 12,
  }, DateTime.utc(2026));
  Future<PendingRecord> raw([String id = 'e1']) async =>
      (await db.readRecord('expenses', id, includeDeleted: true))!;
  RemoteTombstone tombstone([String id = 'e1']) => RemoteTombstone(
    collection: 'expenses',
    id: id,
    ownerId: 'owner',
    deletedAt: DateTime.utc(2026, 9, 25),
    operationId: 'remote-operation',
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('delete-a');
    remote = DeleteTransport();
    connect();
    await db.writeSetting('session', jsonEncode({'id': 'owner'}));
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'markDeleted retains bytes, hides list/find and persists an outbox DELETE',
    () async {
      await create();
      final before = await raw();
      await db.markDeleted('expenses', 'e1', 'owner');
      final after = await raw();
      expect(after.payload['note'], 'preserve me');
      expect(after.isDeleted, true);
      expect(after.operation, 'delete');
      expect(after.ownerId, 'owner');
      expect(after.operationId, isNot(before.operationId));
      expect(after.revision, before.revision + 1);
      expect(await db.readRecords('expenses'), isEmpty);
      expect(await db.readRecord('expenses', 'e1'), isNull);
      expect((await db.readPendingRecords()).single.operation, 'delete');
      expect(await db.pendingCount(), 1);
    },
  );
  test('DELETE survives restart with the same identity and revision', () async {
    await create();
    await db.markDeleted('expenses', 'e1', 'owner');
    final before = await raw();
    await db.close();
    connect();
    final after = await raw();
    expect(after.payload, before.payload);
    expect(await db.pendingCount(), 1);
  });
  test(
    'repeating local DELETE preserves intent before and after confirmation',
    () async {
      await create();
      await db.markDeleted('expenses', 'e1', 'owner');
      final before = await raw();
      await db.markDeleted('expenses', 'e1', 'owner');
      expect((await raw()).payload, before.payload);
      await sync.pushPendingChanges();
      final confirmed = await raw();
      await db.markDeleted('expenses', 'e1', 'owner');
      expect((await raw()).payload, confirmed.payload);
      expect(await db.pendingCount(), 0);
      expect(remote.deletes, 1);
    },
  );
  test(
    'an old UPSERT acknowledgement cannot acknowledge a newer DELETE',
    () async {
      await create();
      final old = await raw();
      await db.markDeleted('expenses', 'e1', 'owner');
      expect(await SyncLocalDataSource(db).acknowledge(old), false);
      expect(await db.pendingCount(), 1);
      expect((await raw()).isDeleted, true);
    },
  );
  test(
    'same timestamp edit has new operationId/revision and rejects stale acknowledgement',
    () async {
      await create();
      final old = await raw();
      await create();
      expect((await raw()).operationId, isNot(old.operationId));
      expect((await raw()).revision, old.revision + 1);
      expect(await SyncLocalDataSource(db).acknowledge(old), false);
      expect(await db.pendingCount(), 1);
    },
  );
  test(
    'active refresh cannot resurrect pending or confirmed local DELETE',
    () async {
      await create();
      await db.markDeleted('expenses', 'e1', 'owner');
      await db.putRecord(
        'expenses',
        'e1',
        {'id': 'e1'},
        DateTime.now(),
        pending: false,
      );
      expect((await raw()).isDeleted, true);
      expect(await db.pendingCount(), 1);
      await sync.pushPendingChanges();
      await db.putRecord(
        'expenses',
        'e1',
        {'id': 'e1'},
        DateTime.now(),
        pending: false,
      );
      expect((await raw()).isDeleted, true);
      expect(await db.pendingCount(), 0);
      expect(await db.readRecords('expenses'), isEmpty);
    },
  );
  test(
    'remote tombstone hides a clean local row and preserves payload',
    () async {
      await create();
      await sync.pushPendingChanges();
      await db.mergeRemoteTombstones('owner', [tombstone()]);
      expect(await db.readRecords('expenses'), isEmpty);
      expect((await raw()).payload['note'], 'preserve me');
      expect(await db.pendingCount(), 0);
    },
  );
  test(
    'remote DELETE wins over local UPSERT and records deterministic conflict',
    () async {
      await create();
      await db.mergeRemoteTombstones('owner', [tombstone()]);
      final once = await raw();
      expect(SyncMetadata.read(once.payload)['conflict'], 'remote_delete_wins');
      expect(await db.pendingCount(), 0);
      await db.mergeRemoteTombstones('owner', [tombstone()]);
      expect((await raw()).payload, once.payload);
      await sync.pushPendingChanges();
      expect(remote.upserts, 0);
    },
  );
  test('remote absence is not a deletion', () async {
    await create();
    await sync.pushPendingChanges();
    await sync.pullRemoteTombstones();
    expect(await db.readRecords('expenses'), hasLength(1));
  });
  test(
    'tombstone received before active record prevents delayed creation',
    () async {
      await db.mergeRemoteTombstones('owner', [tombstone()]);
      await db.putRecord(
        'expenses',
        'e1',
        {'id': 'e1'},
        DateTime.now(),
        pending: false,
      );
      expect(await db.readRecords('expenses'), isEmpty);
      await expectLater(create(), throwsStateError);
    },
  );
  test(
    'wrong owner cannot delete or process another account operation',
    () async {
      await create();
      await expectLater(
        db.markDeleted('expenses', 'e1', 'other'),
        throwsStateError,
      );
      await db.markDeleted('expenses', 'e1', 'owner');
      remote.currentUserId = 'other';
      await sync.pushPendingChanges();
      expect(remote.deletes, 0);
      expect(await db.pendingCount(), 1);
    },
  );
  test(
    'switching both local and remote session cannot adopt an older DELETE',
    () async {
      await create();
      await db.markDeleted('expenses', 'e1', 'owner');
      await db.writeSetting('session', jsonEncode({'id': 'other'}));
      remote.currentUserId = 'other';
      await sync.pushPendingChanges();
      expect(remote.deletes, 0);
      expect((await raw()).ownerId, 'owner');
      expect(await db.pendingCount(), 1);
    },
  );
  test('account switch during RPC does not acknowledge response', () async {
    await create();
    await db.markDeleted('expenses', 'e1', 'owner');
    remote.beforeDelete = () async {
      await db.writeSetting('session', jsonEncode({'id': 'other'}));
      remote.currentUserId = 'other';
    };
    await sync.pushPendingChanges();
    expect(await db.pendingCount(), 1);
  });
  test('logout and clearAll cannot destroy pending DELETE', () async {
    await create();
    await db.markDeleted('expenses', 'e1', 'owner');
    await expectLater(
      db.beginSessionClose(),
      throwsA(isA<PendingSessionChanges>()),
    );
    await expectLater(db.clearAll(), throwsA(isA<PendingSessionChanges>()));
    expect(await db.pendingCount(), 1);
    expect(db.isClosingSession, false);
    await expectLater(db.removeRecord('expenses', 'e1'), throwsStateError);
    await expectLater(db.markAllSynced(), throwsStateError);
    await expectLater(db.markRecordSynced('expenses', 'e1'), throwsStateError);
  });
  test('normal UPSERT continues to publish and acknowledge', () async {
    await create();
    await sync.pushPendingChanges();
    expect(remote.upserts, 1);
    expect(await db.pendingCount(), 0);
    expect(await db.readRecords('expenses'), hasLength(1));
  });
  test('two simultaneous sync calls share the pending DELETE', () async {
    await create();
    await db.markDeleted('expenses', 'e1', 'owner');
    final gate = Completer<void>();
    final started = Completer<void>();
    remote.beforeDelete = () {
      started.complete();
      return gate.future;
    };
    final first = sync.pushPendingChanges();
    await started.future;
    final second = sync.pushPendingChanges();
    gate.complete();
    await Future.wait([first, second]);
    expect(remote.deletes, 1);
    expect(await db.pendingCount(), 0);
  });
  test(
    'unconfirmed response can retry the same remote terminal operation',
    () async {
      await create();
      await db.markDeleted('expenses', 'e1', 'owner');
      final original = await raw();
      final one = await remote.softDelete(original);
      final two = await remote.softDelete(original);
      expect(two.operationId, one.operationId);
      expect(two.deletedAt, one.deletedAt);
      expect(remote.ledger, hasLength(1));
      await db.acknowledgeDelete(original, two);
      expect(await db.pendingCount(), 0);
    },
  );
  test(
    'server rejection of stale upsert resolves through authenticated tombstone',
    () async {
      await create();
      remote.ledger['e1'] = tombstone();
      await sync.pushPendingChanges();
      expect((await raw()).isDeleted, true);
      expect(await db.pendingCount(), 0);
    },
  );
  test('pending edit wins over active download', () async {
    await create();
    final before = await raw();
    await db.putRecord(
      'expenses',
      'e1',
      {'id': 'e1', 'note': 'old server'},
      DateTime.now(),
      pending: false,
    );
    expect((await raw()).payload, before.payload);
    expect(await db.pendingCount(), 1);
  });
  test(
    'legacy without evidence stays unverified and is not sent or lost',
    () async {
      await db.customStatement('INSERT INTO records VALUES (?, ?, ?, ?, ?)', [
        'expenses',
        'e1',
        jsonEncode({'id': 'e1', 'note': 'legacy'}),
        0,
        1,
      ]);
      await sync.pushPendingChanges();
      expect(remote.upserts, 0);
      expect(await db.pendingCount(), 1);
      await expectLater(
        db.markDeleted('expenses', 'e1', 'owner'),
        throwsStateError,
      );
      remote.verified = true;
      await sync.pushPendingChanges();
      expect(remote.upserts, 1);
      expect((await raw()).ownerId, 'owner');
    },
  );
  test(
    'fresh authenticated remote read records ownership for later offline DELETE',
    () async {
      await db.putRecord(
        'expenses',
        'e1',
        {'id': 'e1'},
        DateTime.now(),
        pending: false,
        verifiedRemoteOwner: 'owner',
      );
      await db.markDeleted('expenses', 'e1', 'owner');
      expect((await raw()).ownerId, 'owner');
      expect(await db.pendingCount(), 1);
    },
  );
  test(
    'clean legacy row can be verified explicitly before an offline delete',
    () async {
      await db.putRecord(
        'expenses',
        'e1',
        {'id': 'e1'},
        DateTime.now(),
        pending: false,
      );
      expect(
        await sync.verifyLegacyOwnership('expenses', 'e1', 'owner'),
        false,
      );
      remote.verified = true;
      expect(await sync.verifyLegacyOwnership('expenses', 'e1', 'owner'), true);
      await sync.markDeleted('expenses', 'e1', 'owner');
      expect((await raw()).isDeleted, true);
    },
  );
}
