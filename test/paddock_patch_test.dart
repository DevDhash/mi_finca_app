import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_patch.dart';
import 'package:mi_finca_app/features/paddocks/data/models/paddock_model.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';
import 'delete_a_test.dart' show DeleteTransport;

class PatchTransport extends DeleteTransport
    implements PaddockPatchRemoteDataSource {
  final edits = <Map<String, Object?>>[];
  final full = <PendingRecord>[];
  Future<void> Function()? onPatch;
  @override
  Future<String?> paddockVersion(String id, String owner) async => 'v1';
  @override
  Future<void> pushPaddockPatch(PendingRecord command) async {
    edits.add(
      PaddockPatch.fromLocal(
        Map<String, Object?>.from(command.payload['fields'] as Map),
      ).remoteValues,
    );
    await onPatch?.call();
  }

  @override
  Future<void> pushRecord(PendingRecord record) async {
    full.add(record);
  }
}

void main() {
  late Directory dir;
  late AppDatabase db;
  void open() => db = AppDatabase(NativeDatabase(File('${dir.path}/db')));
  final initial = <String, Object?>{
    'id': 'p',
    'name': 'B',
    'areaHectares': 2.0,
    'pastureType': 'Pasto',
    'status': 'Disponible',
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-01T00:00:00Z',
  };
  Future<PendingRecord> row() async =>
      (await db.readRecord('paddocks', 'p', includeDeleted: true))!;
  Future<List<PendingRecord>> patches() =>
      db.paddockPatches('owner', entityId: 'p');
  Future<String?> edit(Map<PaddockField, Object?> fields) =>
      db.applyPaddockPatch('p', 'owner', PaddockPatch(fields));
  Future<void> move() => db.projectPaddockMove(
    'p',
    'owner',
    'm1',
    PaddockPatch({
      PaddockField.status: 'En uso',
      PaddockField.grazingStartDate: DateTime.utc(2026),
      PaddockField.plannedGrazingDays: 4,
    }),
  );
  Future<void> complete() async {
    expect(
      await db.completePaddockMoveProjection(await row(), 'm1', {
        ...initial,
        'user_id': 'owner',
        'deleted_at': null,
        'status': 'Descansando',
      }),
      true,
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('patch');
    open();
    await db.writeSetting('session', jsonEncode({'id': 'owner'}));
    await db.putRecord(
      'paddocks',
      'p',
      initial,
      DateTime.utc(2026),
      pending: false,
      verifiedRemoteOwner: 'owner',
    );
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  for (final item in [
    (PaddockField.name, 'Norte', 'name'),
    (PaddockField.area, 3.0, 'areaHectares'),
  ]) {
    test(
      '${item.$3} edit persists only intended field and updates projection',
      () async {
        await edit({item.$1: item.$2});
        expect((await patches()).single.payload['fields'], {item.$3: item.$2});
        expect((await row()).payload[item.$3], item.$2);
      },
    );
    test(
      'MOVE then ${item.$3} waits, publishes only patch after explicit completion',
      () async {
        await move();
        await edit({item.$1: item.$2});
        final remote = PatchTransport();
        final sync = SyncRepositoryImpl(SyncLocalDataSource(db), remote);
        await sync.pushPendingChanges();
        expect(remote.edits, isEmpty);
        expect(remote.full, isEmpty);
        await complete();
        await sync.pushPendingChanges();
        expect(remote.full, isEmpty);
        expect(remote.edits, [
          PaddockPatch({item.$1: item.$2}).remoteValues,
        ]);
        expect((await row()).payload['status'], 'Descansando');
      },
    );
  }
  test('null is explicit and legacy alias also cleared', () async {
    await edit({PaddockField.pastureType: null});
    final command = (await patches()).single;
    expect((command.payload['fields'] as Map).containsKey('pastureType'), true);
    expect((command.payload['fields'] as Map).containsKey('name'), false);
    expect(PaddockModel.fromJson((await row()).payload).pastureType, isNull);
  });
  test('restart preserves identity owner order and fields', () async {
    await edit({PaddockField.name: 'Norte'});
    final before = (await patches()).single;
    await db.close();
    open();
    expect((await patches()).single.payload, before.payload);
  });
  test(
    'multiple patches publish in durable order, ACK never rewrites newer local edit',
    () async {
      await edit({PaddockField.name: 'E1'});
      await edit({PaddockField.area: 8.0});
      await edit({PaddockField.name: 'E3'});
      final remote = PatchTransport();
      await SyncRepositoryImpl(
        SyncLocalDataSource(db),
        remote,
      ).pushPendingChanges();
      expect(remote.edits, [
        {'name': 'E1'},
        {'area': 8.0},
        {'name': 'E3'},
      ]);
      expect((await row()).payload['name'], 'E3');
      expect((await row()).payload['areaHectares'], 8.0);
    },
  );
  test('operational edit during MOVE is explicit durable conflict', () async {
    await move();
    await edit({PaddockField.plannedGrazingDays: 6});
    expect((await patches()).single.payload['state'], 'conflict');
    expect((await row()).payload['plannedGrazingDays'], 4);
    await db.close();
    open();
    expect((await patches()).single.payload['fields'], {
      'plannedGrazingDays': 6,
    });
  });
  test(
    'intentional operational edit without MOVE publishes only requested field',
    () async {
      await edit({PaddockField.plannedGrazingDays: 6});
      final remote = PatchTransport();
      await SyncRepositoryImpl(
        SyncLocalDataSource(db),
        remote,
      ).pushPendingChanges();
      expect(remote.edits, [
        {'planned_grazing_days': 6},
      ]);
    },
  );
  test(
    'remote refresh merges operational state and reapplies pending name',
    () async {
      await edit({PaddockField.name: 'Norte'});
      await db.putRecord(
        'paddocks',
        'p',
        {...initial, 'status': 'Descansando'},
        DateTime.now(),
        pending: false,
        verifiedRemoteOwner: 'owner',
      );
      expect((await row()).payload['name'], 'Norte');
      expect((await row()).payload['status'], 'Descansando');
    },
  );
  test(
    'terminal tombstone conflicts patch and cannot revive projection',
    () async {
      await edit({PaddockField.name: 'Norte'});
      await db.mergeRemoteTombstones('owner', [
        RemoteTombstone(
          collection: 'paddocks',
          id: 'p',
          ownerId: 'owner',
          deletedAt: DateTime.now(),
          operationId: 'terminal',
        ),
      ]);
      expect((await patches()).single.payload['state'], 'conflict');
      expect(await db.readRecord('paddocks', 'p'), isNull);
      await expectLater(edit({PaddockField.name: 'revive'}), throwsStateError);
    },
  );
  for (final conflict in [false, true]) {
    test('delete ${conflict ? 'conflict' : 'pending'} blocks edit', () async {
      await db.markDeleted('paddocks', 'p', 'owner');
      if (conflict) {
        await db.rejectPaddockDelete(await row(), 'SYNC_PADDOCK_OCCUPIED');
      }
      await expectLater(edit({PaddockField.name: 'Norte'}), throwsStateError);
      expect(await patches(), isEmpty);
    });
  }
  test('owner mismatch cannot edit or process', () async {
    await edit({PaddockField.name: 'Norte'});
    await db.writeSetting('session', jsonEncode({'id': 'other'}));
    await expectLater(edit({PaddockField.name: 'X'}), throwsStateError);
    final remote = PatchTransport()..currentUserId = 'other';
    await SyncRepositoryImpl(
      SyncLocalDataSource(db),
      remote,
    ).pushPendingChanges();
    expect(remote.edits, isEmpty);
  });
  test(
    'legacy pending snapshot is not guessed into patch; initial publication frozen',
    () async {
      await db.putRecord('paddocks', 'p', initial, DateTime.now());
      expect(await patches(), isEmpty);
      await edit({PaddockField.name: 'Norte'});
      final r = await row();
      expect((r.payload['_basePaddockWrite'] as Map)['name'], 'B');
      expect(r.payload['name'], 'Norte');
      final remote = PatchTransport();
      await SyncRepositoryImpl(
        SyncLocalDataSource(db),
        remote,
      ).pushPendingChanges();
      expect(remote.full.length, 1);
      expect(remote.edits, [
        {'name': 'Norte'},
      ]);
    },
  );
  test(
    'CREATE remains full and projection refuses unpublished dependency',
    () async {
      await db.putRecord('paddocks', 'new', {
        ...initial,
        'id': 'new',
      }, DateTime.now());
      final r = (await db.readRecord('paddocks', 'new'))!;
      expect(SyncMetadata.read(r.payload)['writeKind'], 'create');
      expect(r.payload['name'], 'B');
      await expectLater(
        db.projectPaddockMove(
          'new',
          'owner',
          'm',
          PaddockPatch({PaddockField.status: 'En uso'}),
        ),
        throwsStateError,
      );
    },
  );
  test('legacy full save cannot overwrite an unresolved patch', () async {
    await edit({PaddockField.name: 'Norte'});
    await expectLater(
      db.putRecord('paddocks', 'p', initial, DateTime.now()),
      throwsStateError,
    );
  });
  test('conflict and MOVE markers protect logout and local cleanup', () async {
    await move();
    await edit({PaddockField.plannedGrazingDays: 6});
    await expectLater(
      db.beginSessionClose(),
      throwsA(isA<PendingSessionChanges>()),
    );
    await expectLater(db.clearAll(), throwsA(isA<PendingSessionChanges>()));
    await expectLater(
      db.removeRecord('paddocks', 'p'),
      throwsA(isA<PendingSessionChanges>()),
    );
  });
  test(
    'failed local patch transaction leaves neither intent nor projection',
    () async {
      await expectLater(
        db.runInTransaction(() async {
          await edit({PaddockField.name: 'Norte'});
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await patches(), isEmpty);
      expect((await row()).payload['name'], 'B');
    },
  );
  test('concurrent sync coalesces sends', () async {
    await edit({PaddockField.name: 'Norte'});
    final remote = PatchTransport();
    final sync = SyncRepositoryImpl(SyncLocalDataSource(db), remote);
    await Future.wait([sync.pushPendingChanges(), sync.pushPendingChanges()]);
    expect(remote.edits.length, 1);
  });
  test(
    'uncertain delivery retains original remote version and blocks later patches',
    () async {
      await edit({PaddockField.name: 'E1'});
      await edit({PaddockField.area: 3.0});
      final remote = PatchTransport()
        ..onPatch = () async {
          throw const SocketException('lost');
        };
      final sync = SyncRepositoryImpl(SyncLocalDataSource(db), remote);
      await sync.pushPendingChanges();
      await sync.pushPendingChanges();
      expect(remote.edits, [
        {'name': 'E1'},
        {'name': 'E1'},
      ]);
      expect((await patches()).first.payload['remoteBaseVersion'], 'v1');
    },
  );
  test('ACK during later edit never rewinds new projection', () async {
    await edit({PaddockField.name: 'E1'});
    final remote = PatchTransport();
    remote.onPatch = () async {
      await edit({PaddockField.name: 'E2'});
    };
    await SyncRepositoryImpl(
      SyncLocalDataSource(db),
      remote,
    ).pushPendingChanges();
    expect((await row()).payload['name'], 'E2');
    expect((await patches()).map((r) => r.payload['state']), [
      'completed',
      'pending',
    ]);
  });
  test('late patch ACK cannot override terminal conflict', () async {
    await edit({PaddockField.name: 'E1'});
    final before = (await patches()).single;
    await db.mergeRemoteTombstones('owner', [
      RemoteTombstone(
        collection: 'paddocks',
        id: 'p',
        ownerId: 'owner',
        deletedAt: DateTime.now(),
        operationId: 'terminal',
      ),
    ]);
    expect(await db.finishPaddockPatch(before), false);
    expect((await patches()).single.payload['state'], 'conflict');
  });
  test('blanket ACK cannot bypass patches', () async {
    await edit({PaddockField.name: 'E1'});
    await expectLater(db.markAllSynced(), throwsStateError);
    await expectLater(
      db.markRecordSynced(paddockPatchCollection, (await patches()).single.id),
      throwsStateError,
    );
    expect((await patches()).single.payload['state'], 'pending');
  });
  test('DELETE ACK makes pending patches conflict immediately', () async {
    await edit({PaddockField.name: 'E1'});
    await db.markDeleted('paddocks', 'p', 'owner');
    await db.acknowledgeDelete(
      await row(),
      RemoteTombstone(
        collection: 'paddocks',
        id: 'p',
        ownerId: 'owner',
        deletedAt: DateTime.now(),
        operationId: 'terminal',
      ),
    );
    expect((await patches()).single.payload['state'], 'conflict');
    expect(await db.pendingCount(), 0);
  });
}
