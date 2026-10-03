import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/core/database/sync_failure.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';
import 'delete_a_test.dart' show DeleteTransport;

void main() {
  late Directory dir;
  late AppDatabase db;
  void open() => db = AppDatabase(NativeDatabase(File('${dir.path}/db')));
  Future<PendingRecord> row() async =>
      (await db.readRecord('paddocks', 'p', includeDeleted: true))!;
  Future<void> intent() => db.markDeleted('paddocks', 'p', 'owner');
  RemoteTombstone terminal() => RemoteTombstone(
    collection: 'paddocks',
    id: 'p',
    ownerId: 'owner',
    deletedAt: DateTime.utc(2026),
    operationId: 'server',
  );
  Future<bool> reject(PendingRecord r) =>
      db.rejectPaddockDelete(r, 'SYNC_PADDOCK_OCCUPIED');
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('deletion-state');
    open();
    await db.writeSetting('session', jsonEncode({'id': 'owner'}));
    await db.putRecord('paddocks', 'p', {
      'id': 'p',
      'name': 'P',
    }, DateTime.utc(2026));
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'pending survives restart and duplicate intent with stable identity',
    () async {
      await intent();
      final before = await row();
      expect(SyncMetadata.deletionState(before.payload), DeletionState.pending);
      await db.close();
      open();
      await intent();
      expect((await row()).payload, before.payload);
      expect(await db.pendingCount(), 1);
    },
  );
  for (final evidence in ['ack', 'ledger']) {
    test(
      '$evidence confirms terminal; ordinary writes and CAS cannot revive',
      () async {
        await intent();
        if (evidence == 'ack') {
          await db.acknowledgeDelete(await row(), terminal());
        } else {
          await db.mergeRemoteTombstones('owner', [terminal()]);
        }
        final r = await row();
        expect(SyncMetadata.deletionState(r.payload), DeletionState.confirmed);
        expect(await db.pendingCount(), 0);
        await expectLater(
          db.putRecord('paddocks', 'p', {'id': 'p'}, DateTime.now()),
          throwsStateError,
        );
        expect(
          await db.replaceRecordIfUnchanged(r, {'id': 'p'}, pending: false),
          false,
        );
        expect(await reject(r), false);
        expect(
          await db.reconcileRejectedPaddockDelete(
            r,
            remoteOwner: 'owner',
            activePayload: {'id': 'p', 'user_id': 'owner', 'deleted_at': null},
          ),
          false,
        );
      },
    );
  }
  test(
    'conflict survives restart, hides, blocks logout and can reconcile explicitly',
    () async {
      await intent();
      final before = await row();
      expect(await reject(before), true);
      await db.close();
      open();
      final r = await row();
      expect(r.operationId, before.operationId);
      expect(SyncMetadata.deletionState(r.payload), DeletionState.conflict);
      expect(await db.pendingCount(), 0);
      expect(await db.readRecords('paddocks'), isEmpty);
      await expectLater(
        db.beginSessionClose(),
        throwsA(isA<PendingSessionChanges>()),
      );
      await expectLater(db.clearAll(), throwsA(isA<PendingSessionChanges>()));
      await db.putRecord(
        'paddocks',
        'p',
        {'id': 'p'},
        DateTime.now(),
        pending: false,
      );
      expect((await row()).payload, r.payload);
      await db.mergeRemoteTombstones('owner', []);
      expect((await row()).payload, r.payload);
      expect(
        await db.reconcileRejectedPaddockDelete(
          r,
          remoteOwner: 'owner',
          activePayload: {
            'id': 'p',
            'name': 'Remote',
            'user_id': 'owner',
            'deleted_at': null,
          },
        ),
        true,
      );
      expect((await db.readRecords('paddocks')).single['name'], 'Remote');
      await expectLater(
        db.removeRecord('paddocks', 'p'),
        throwsA(isA<PendingSessionChanges>()),
      );
      expect((await row()).operationId, before.operationId);
      expect(await reject(before), false);
    },
  );
  test(
    'ledger beats conflict and late rejection/ACK cannot overwrite it',
    () async {
      await intent();
      final pending = await row();
      await reject(pending);
      final conflict = await row();
      await db.mergeRemoteTombstones('owner', [terminal()]);
      expect(await reject(pending), false);
      expect(await db.acknowledgeDelete(pending, terminal()), false);
      expect(
        await db.reconcileRejectedPaddockDelete(
          conflict,
          remoteOwner: 'owner',
          activePayload: {'id': 'p', 'user_id': 'owner', 'deleted_at': null},
        ),
        false,
      );
      expect(
        SyncMetadata.deletionState((await row()).payload),
        DeletionState.confirmed,
      );
    },
  );
  test(
    'pending cannot be restored by active refresh or reconciliation',
    () async {
      await intent();
      final r = await row();
      await db.putRecord(
        'paddocks',
        'p',
        {'id': 'p'},
        DateTime.now(),
        pending: false,
      );
      expect((await row()).payload, r.payload);
      expect(
        await db.reconcileRejectedPaddockDelete(
          r,
          remoteOwner: 'owner',
          activePayload: {'id': 'p', 'user_id': 'owner', 'deleted_at': null},
        ),
        false,
      );
    },
  );
  test('stale revision cannot reject or ACK', () async {
    await intent();
    final old = await row();
    await db.replaceRecordIfUnchanged(old, {
      ...old.payload,
      '_sync': {
        ...SyncMetadata.read(old.payload),
        'revision': old.revision + 1,
      },
    }, pending: true);
    expect(await reject(old), false);
    expect(await db.acknowledgeDelete(old, terminal()), false);
  });
  test('wrong account cannot reject, reconcile or process', () async {
    await intent();
    final r = await row();
    await db.writeSetting('session', jsonEncode({'id': 'other'}));
    await expectLater(reject(r), throwsStateError);
    await expectLater(
      db.reconcileRejectedPaddockDelete(
        r,
        remoteOwner: 'owner',
        activePayload: {'id': 'p', 'user_id': 'owner', 'deleted_at': null},
      ),
      throwsStateError,
    );
    final remote = DeleteTransport()..currentUserId = 'other';
    await SyncRepositoryImpl(
      SyncLocalDataSource(db),
      remote,
    ).pushPendingChanges();
    expect(remote.deletes, 0);
  });
  for (final transient in [true, false]) {
    test(
      'sync ${transient ? 'transient retries' : 'business conflict stops retries'}',
      () async {
        await intent();
        final remote = DeleteTransport();
        remote.beforeDelete = () async {
          if (transient) throw const SocketException('offline');
          throw const PostgrestException(
            message: 'SYNC_PADDOCK_OCCUPIED',
            code: 'P0001',
          );
        };
        final sync = SyncRepositoryImpl(SyncLocalDataSource(db), remote);
        await sync.pushPendingChanges();
        await sync.pushPendingChanges();
        expect(remote.deletes, transient ? 2 : 1);
        expect(await db.pendingCount(), transient ? 1 : 0);
      },
    );
  }
  for (final collection in ['expenses', 'animals', 'paddocks']) {
    test('legacy confirmed $collection stays terminal', () async {
      final payload = {
        'id': 'legacy',
        '_sync': {
          'ownerId': 'owner',
          'operation': 'delete',
          'tombstone': true,
          'deletedAt': '2026-01-01T00:00:00Z',
          'remoteOperationId': 'remote',
        },
      };
      expect(SyncMetadata.deletionState(payload), DeletionState.confirmed);
    });
  }
  test('classification never treats an error as ACK', () {
    expect(
      SyncFailure.classify(const SocketException('offline')),
      SyncFailureKind.transient,
    );
    expect(
      SyncFailure.classify(
        const PostgrestException(message: 'SYNC_ENTITY_DELETED', code: 'P0001'),
      ),
      SyncFailureKind.terminalEvidenceRequired,
    );
    expect(
      SyncFailure.classify(
        const PostgrestException(message: 'denied', code: '42501'),
      ),
      SyncFailureKind.authorizationFatal,
    );
  });
  test(
    'legacy pending is identified using SQL pending, never ACK absence alone',
    () async {
      await intent();
      final r = await row();
      final payload = {
        ...r.payload,
        '_sync': {...SyncMetadata.read(r.payload)}..remove('deletionState'),
      };
      await db.customStatement(
        'UPDATE records SET payload = ? WHERE collection = ? AND id = ?',
        [jsonEncode(payload), 'paddocks', 'p'],
      );
      expect(await db.deletionState('paddocks', 'p'), DeletionState.pending);
      expect(await reject(await row()), true);
      expect(await db.deletionState('paddocks', 'p'), DeletionState.conflict);
    },
  );
  test(
    'legacy unclassified tombstone remains protected, never guessed pending',
    () async {
      await intent();
      final r = await row();
      final payload = {
        ...r.payload,
        '_sync': {...SyncMetadata.read(r.payload)}..remove('deletionState'),
      };
      await db.customStatement(
        'UPDATE records SET payload = ?, pending = 0 WHERE collection = ? AND id = ?',
        [jsonEncode(payload), 'paddocks', 'p'],
      );
      expect(
        await db.deletionState('paddocks', 'p'),
        DeletionState.legacyUnknown,
      );
      expect(await reject(await row()), false);
      await expectLater(
        db.putRecord('paddocks', 'p', {'id': 'p'}, DateTime.now()),
        throwsStateError,
      );
    },
  );
  test(
    'reconciled conflict audit survives refresh/edit and blocks silent new delete',
    () async {
      await intent();
      final r = await row();
      await reject(r);
      await db.reconcileRejectedPaddockDelete(
        await row(),
        remoteOwner: 'owner',
        activePayload: {'id': 'p', 'user_id': 'owner', 'deleted_at': null},
      );
      await db.putRecord(
        'paddocks',
        'p',
        {'id': 'p', 'name': 'remote'},
        DateTime.now(),
        pending: false,
        verifiedRemoteOwner: 'owner',
      );
      await db.putRecord('paddocks', 'p', {
        'id': 'p',
        'name': 'edit',
      }, DateTime.now());
      final meta = SyncMetadata.read((await row()).payload);
      expect((meta['rejectedDelete'] as Map)['operationId'], r.operationId);
      await expectLater(intent(), throwsStateError);
      await expectLater(db.clearAll(), throwsA(isA<PendingSessionChanges>()));
    },
  );
  test(
    'reconciliation rejects mismatched authoritative owner and entity',
    () async {
      await intent();
      await reject(await row());
      final r = await row();
      for (final payload in [
        {'id': 'p', 'user_id': 'other', 'deleted_at': null},
        {'id': 'other', 'user_id': 'owner', 'deleted_at': null},
        {'id': 'p', 'user_id': 'owner', 'deleted_at': '2026-01-01'},
        {'id': 'p'},
      ]) {
        await expectLater(
          db.reconcileRejectedPaddockDelete(
            r,
            remoteOwner: 'owner',
            activePayload: payload,
          ),
          throwsArgumentError,
        );
      }
    },
  );
  test(
    'terminal evidence cannot be stripped while keeping tombstone true',
    () async {
      await intent();
      await db.acknowledgeDelete(await row(), terminal());
      final r = await row();
      final meta = SyncMetadata.read(r.payload)
        ..remove('deletedAt')
        ..remove('remoteOperationId');
      expect(
        await db.replaceRecordIfUnchanged(r, {
          ...r.payload,
          '_sync': meta,
        }, pending: true),
        false,
      );
    },
  );
  test('unclassified error cannot create business conflict', () async {
    await intent();
    await expectLater(
      db.rejectPaddockDelete(await row(), 'timeout'),
      throwsArgumentError,
    );
    expect(await db.pendingCount(), 1);
  });
  test('session changes during rejection cannot persist conflict', () async {
    await intent();
    final remote = DeleteTransport();
    remote.beforeDelete = () async {
      remote.currentUserId = 'other';
      throw const PostgrestException(
        message: 'SYNC_PADDOCK_OCCUPIED',
        code: 'P0001',
      );
    };
    await SyncRepositoryImpl(
      SyncLocalDataSource(db),
      remote,
    ).pushPendingChanges();
    expect(await db.deletionState('paddocks', 'p'), DeletionState.pending);
    expect(await db.pendingCount(), 1);
  });
  test('conflict ordinary CAS cannot restore or erase rejection', () async {
    await intent();
    await reject(await row());
    final r = await row();
    expect(
      await db.replaceRecordIfUnchanged(r, {'id': 'p'}, pending: false),
      false,
    );
    final meta = SyncMetadata.read(r.payload)..remove('deleteRejection');
    expect(
      await db.replaceRecordIfUnchanged(r, {
        ...r.payload,
        '_sync': meta,
      }, pending: true),
      false,
    );
  });
  test(
    'legacy local cancellation stays protected without remote ACK',
    () async {
      await db.putRecord('animals', 'a', {'id': 'a'}, DateTime.utc(2026));
      expect(
        await db.deleteAnimalLocally('a', 'owner'),
        AnimalLocalDeletion.accepted,
      );
      expect(
        await db.deletionState('animals', 'a'),
        DeletionState.localCancelled,
      );
      await expectLater(
        db.putRecord('animals', 'a', {'id': 'a'}, DateTime.now()),
        throwsStateError,
      );
    },
  );
  test(
    'ledger returned after business rejection wins in same sync pass',
    () async {
      await intent();
      final remote = DeleteTransport()..ledger['p'] = terminal();
      remote.beforeDelete = () async {
        throw const PostgrestException(
          message: 'SYNC_PADDOCK_OCCUPIED',
          code: 'P0001',
        );
      };
      await SyncRepositoryImpl(
        SyncLocalDataSource(db),
        remote,
      ).pushPendingChanges();
      expect(await db.deletionState('paddocks', 'p'), DeletionState.confirmed);
      expect(await db.pendingCount(), 0);
    },
  );
  test('partial legacy ACK evidence is never rejected or reconciled', () async {
    await intent();
    final r = await row();
    await db.replaceRecordIfUnchanged(r, {
      ...r.payload,
      '_sync': {...SyncMetadata.read(r.payload), 'deletedAt': '2026-01-01'},
    }, pending: true);
    expect(await reject(await row()), false);
  });
}
