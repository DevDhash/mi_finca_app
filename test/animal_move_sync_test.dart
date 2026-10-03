import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_patch.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/core/database/sync_failure.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_move_command.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_patch.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';
import 'delete_a_test.dart' show DeleteTransport;

class MoveTransport extends DeleteTransport
    implements AnimalMoveRemoteDataSource {
  final calls = <String>[];
  final receipts = <String, Map<String, Object?>>{};
  bool lost = false;
  bool unavailable = false;
  String? rejection;
  String location = 'B';
  @override
  Future<Map<String, Object?>> pushAnimalMove(PendingRecord r) async {
    calls.add(r.id);
    if (rejection != null) {
      throw PostgrestException(message: rejection!, code: 'P0001');
    }
    final c = AnimalMoveCommand.fromLocal(r.payload);
    final receipt = receipts.putIfAbsent(
      r.id,
      () => {
        'id': c.movementId,
        'user_id': c.ownerId,
        'animal_id': c.animalId,
        'from_paddock_id': c.fromPaddockId,
        'to_paddock_id': c.toPaddockId,
        'moved_at': c.movedAt.toUtc().toIso8601String(),
      },
    );
    if (lost) {
      lost = false;
      throw const SocketException('lost');
    }
    return receipt;
  }

  @override
  Future<Map<String, Object?>> readAnimalMoveState(PendingRecord r) async {
    if (unavailable) throw const SocketException('offline');
    return {
      'animal': {
        'id': 'a',
        'user_id': 'owner',
        'paddock_id': location,
        'deleted_at': null,
      },
      'paddocks': <Map<String, Object?>>[],
    };
  }

  @override
  Future<void> pushRecord(PendingRecord record) async =>
      throw StateError('Unexpected generic MOVE write');
}

class OccupiedPaddockRemote extends DeleteTransport
    implements PaddockReconciliationRemoteDataSource {
  String message = 'SYNC_PADDOCK_OCCUPIED';
  String code = 'P0001';
  @override
  Future<RemoteTombstone> softDelete(PendingRecord record) async =>
      throw PostgrestException(message: message, code: code);
  @override
  Future<Map<String, Object?>?> readActivePaddock(
    String id,
    String owner,
  ) async => {
    'id': id,
    'user_id': owner,
    'deleted_at': null,
    'name': 'Remote',
    'areaHectares': 1,
    'status': 'En uso',
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-01T00:00:00Z',
  };
}

void main() {
  late AppDatabase db;
  late Directory dir;
  late MoveTransport remote;
  void open() => db = AppDatabase(NativeDatabase(File('${dir.path}/db')));
  Future<PendingRecord> command() async =>
      (await db.animalMoveCommands('owner')).single;
  Future<PendingRecord> animal() async =>
      (await db.readRecord('animals', 'a', includeDeleted: true))!;
  Future<void> enqueue() async {
    await db.createAnimalMove(
      command: AnimalMoveCommand(
        movementId: 'm',
        ownerId: 'owner',
        animalId: 'a',
        fromPaddockId: 'A',
        toPaddockId: 'B',
        movedAt: DateTime.utc(2026),
        plannedGrazingDays: 4,
      ),
      movementPayload: {
        'id': 'm',
        'animalId': 'a',
        'fromPaddockId': 'A',
        'toPaddockId': 'B',
        'date': DateTime.utc(2026).toIso8601String(),
      },
    );
  }

  Future<void> sync() =>
      SyncRepositoryImpl(SyncLocalDataSource(db), remote).pushPendingChanges();
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('move-d2');
    open();
    remote = MoveTransport();
    await db.writeSetting('session', jsonEncode({'id': 'owner'}));
    await db.putRecord(
      'animals',
      'a',
      {'id': 'a', 'paddockId': 'A', 'name': 'N'},
      DateTime.utc(2026),
      pending: false,
      verifiedRemoteOwner: 'owner',
    );
    for (final id in ['A', 'B']) {
      await db.putRecord(
        'paddocks',
        id,
        {'id': id, 'name': id},
        DateTime.utc(2026),
        pending: false,
        verifiedRemoteOwner: 'owner',
      );
    }
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
  test(
    'offline command is sole pending write; provisional history localOnly',
    () async {
      await enqueue();
      expect(
        (await db.readPendingRecords()).single.collection,
        animalMoveCollection,
      );
      expect((await animal()).payload['paddockId'], 'B');
      expect(
        (await db.readRecord('movements', 'm'))!.remotePresence,
        RemotePresence.localOnly,
      );
    },
  );
  test('receipt and current state complete without generic writes', () async {
    await enqueue();
    await sync();
    expect((await command()).payload['state'], 'completed');
    expect((await animal()).payload['_moveProjection'], isNull);
    expect(
      (await db.readRecord('movements', 'm'))!.remotePresence,
      RemotePresence.confirmed,
    );
  });
  test('lost response retries same ID after restart', () async {
    await enqueue();
    remote.lost = true;
    await sync();
    expect((await command()).payload['state'], 'pending');
    await db.close();
    open();
    await sync();
    expect(remote.calls, ['m', 'm']);
    expect(remote.receipts.length, 1);
  });
  test(
    'crash after reconciliation before completion retries idempotently',
    () async {
      await enqueue();
      final c = await command();
      final receipt = await remote.pushAnimalMove(c);
      final state = await remote.readAnimalMoveState(c);
      expect(
        await db.reconcileAnimalMoveSuccess(c, movement: receipt, state: state),
        true,
      );
      expect((await command()).payload['state'], 'pending');
      await db.close();
      open();
      await sync();
      expect((await command()).payload['state'], 'completed');
      expect(remote.receipts.length, 1);
    },
  );
  test('crash recovery accepts equivalent ISO receipt instants', () async {
    await enqueue();
    final c = await command();
    final receipt = await remote.pushAnimalMove(c);
    final state = await remote.readAnimalMoveState(c);
    expect(
      await db.reconcileAnimalMoveSuccess(c, movement: receipt, state: state),
      true,
    );
    expect((await command()).payload['state'], 'pending');
    expect((await animal()).payload['_moveProjection'], isNull);
    await db.close();
    open();
    remote.receipts[c.id] = {
      ...receipt,
      'moved_at': '2025-12-31T19:00:00-05:00',
    };
    expect(remote.receipts[c.id]!['moved_at'], isNot(receipt['moved_at']));
    await sync();
    expect(remote.calls, ['m', 'm']);
    expect((await command()).id, c.id);
    expect((await command()).payload['state'], 'completed');
    expect(remote.receipts.length, 1);
  });
  test(
    'later device MOVE current location wins over original receipt',
    () async {
      await enqueue();
      remote.location = 'C';
      await sync();
      expect((await animal()).payload['paddockId'], 'C');
    },
  );
  test(
    'business rejection restores current location not expected source',
    () async {
      await enqueue();
      remote.rejection = 'SYNC_MOVE_SOURCE_CONFLICT';
      remote.location = 'C';
      await sync();
      expect((await command()).payload['state'], 'conflict');
      expect((await animal()).payload['paddockId'], 'C');
      expect((await animal()).payload['_moveProjection'], isNull);
      expect(await AnimalLocalDataSource(db).getMovements(), isEmpty);
    },
  );
  test(
    'offline rejection stays recoverable and hides provisional history',
    () async {
      await enqueue();
      remote.rejection = 'SYNC_PADDOCK_NOT_AVAILABLE';
      remote.unavailable = true;
      await sync();
      expect(
        (await animal()).payload['_moveProjection'],
        containsPair('rejected', true),
      );
      expect(await AnimalLocalDataSource(db).getMovements(), isEmpty);
      await db.close();
      open();
      remote.unavailable = false;
      remote.location = 'C';
      await sync();
      expect(remote.calls, ['m']);
      expect((await command()).payload['reconciled'], true);
    },
  );
  test('generic ACK remove clear and logout cannot discard MOVE', () async {
    await enqueue();
    await expectLater(db.markAllSynced(), throwsStateError);
    await expectLater(
      db.markRecordSynced(animalMoveCollection, 'm'),
      throwsStateError,
    );
    await expectLater(
      db.removeRecord(animalMoveCollection, 'm'),
      throwsA(isA<PendingSessionChanges>()),
    );
    await expectLater(db.clearAll(), throwsA(isA<PendingSessionChanges>()));
    await expectLater(
      db.beginSessionClose(),
      throwsA(isA<PendingSessionChanges>()),
    );
  });
  test('terminal wins while accepted history is preserved', () async {
    await enqueue();
    final c = await command();
    final receipt = await remote.pushAnimalMove(c);
    await db.mergeRemoteTombstones('owner', [
      RemoteTombstone(
        collection: 'animals',
        id: 'a',
        ownerId: 'owner',
        operationId: 'd',
        deletedAt: DateTime.utc(2026),
      ),
    ]);
    expect(
      await db.reconcileAnimalMoveSuccess(
        c,
        movement: receipt,
        state: {'animal': null, 'paddocks': []},
      ),
      true,
    );
    expect((await animal()).isDeleted, true);
    expect(
      (await db.readRecord('movements', 'm'))!.remotePresence,
      RemotePresence.confirmed,
    );
  });
  test('independent name patch survives reconcile', () async {
    await enqueue();
    await db.applyAnimalPatch(
      'a',
      'owner',
      AnimalPatch({AnimalField.name: 'Edited'}),
    );
    await sync();
    expect((await animal()).payload['name'], 'Edited');
    expect(
      (await db.animalPatches('owner')).single.payload['state'],
      'pending',
    );
  });
  test('paddock occupancy and pending MOVE block local delete', () async {
    await expectLater(
      db.markDeleted('paddocks', 'A', 'owner'),
      throwsStateError,
    );
    await enqueue();
    await expectLater(
      db.markDeleted('paddocks', 'A', 'owner'),
      throwsStateError,
    );
  });
  test('unknown/auth errors cannot become business conflicts by substring', () {
    expect(
      SyncFailure.classify(
        const PostgrestException(
          message: 'unknown SYNC_MOVE_SOURCE_CONFLICT',
          code: 'P0001',
        ),
      ),
      SyncFailureKind.transient,
    );
    expect(
      SyncFailure.classify(
        const PostgrestException(
          message: 'SYNC_MOVE_SOURCE_CONFLICT',
          code: '42501',
        ),
      ),
      SyncFailureKind.authorizationFatal,
    );
  });
  test('missing current animal is not deletion or ACK', () async {
    await enqueue();
    final c = await command();
    final receipt = await remote.pushAnimalMove(c);
    expect(
      await db.reconcileAnimalMoveSuccess(
        c,
        movement: receipt,
        state: {'animal': null, 'paddocks': []},
      ),
      false,
    );
    expect(await db.completeAnimalMoveCommand(c), false);
    expect((await animal()).isDeleted, false);
  });
  test('deleted historical paddock does not strand accepted history', () async {
    await enqueue();
    final c = await command();
    final receipt = await remote.pushAnimalMove(c);
    final state = await remote.readAnimalMoveState(c);
    state['paddocks'] = [
      {'id': 'A', 'user_id': 'owner', 'deleted_at': '2026-01-01T00:00:00Z'},
    ];
    expect(
      await db.reconcileAnimalMoveSuccess(c, movement: receipt, state: state),
      true,
    );
    expect(await db.completeAnimalMoveCommand(c), true);
  });
  test('all installed business codes and terminal errors classify exactly', () {
    for (final code in [
      'SYNC_PADDOCK_OCCUPIED',
      'SYNC_MOVE_SOURCE_CONFLICT',
      'SYNC_PADDOCK_NOT_AVAILABLE',
      'SYNC_GRAZING_DAYS_REQUIRED',
      'SYNC_MOVE_ID_CONFLICT',
      'SYNC_MOVE_LEGACY_CONFLICT',
    ]) {
      expect(
        SyncFailure.classify(
          PostgrestException(
            message: code,
            code: code == 'SYNC_GRAZING_DAYS_REQUIRED' ? '22023' : 'P0001',
          ),
        ),
        SyncFailureKind.businessConflict,
      );
    }
    expect(
      SyncFailure.classify(
        const PostgrestException(message: 'SYNC_ENTITY_DELETED', code: 'P0001'),
      ),
      SyncFailureKind.terminalEvidenceRequired,
    );
  });
  test('generic CAS cannot acknowledge a MOVE command', () async {
    await enqueue();
    final c = await command();
    expect(
      () => db.replaceRecordIfUnchanged(c, c.payload, pending: false),
      throwsStateError,
    );
    expect((await command()).payload['state'], 'pending');
  });
  test(
    'crash gap cannot queue a second MOVE before first command ACK',
    () async {
      await enqueue();
      final c = await command();
      await db.reconcileAnimalMoveSuccess(
        c,
        movement: await remote.pushAnimalMove(c),
        state: await remote.readAnimalMoveState(c),
      );
      await expectLater(
        db.createAnimalMove(
          command: AnimalMoveCommand(
            movementId: 'm2',
            ownerId: 'owner',
            animalId: 'a',
            fromPaddockId: 'B',
            toPaddockId: 'A',
            movedAt: DateTime.utc(2026),
          ),
          movementPayload: {},
        ),
        throwsStateError,
      );
    },
  );
  test(
    'paddock descriptive patch survives authoritative operational state',
    () async {
      await enqueue();
      await db.applyPaddockPatch(
        'B',
        'owner',
        PaddockPatch({PaddockField.name: 'Nuevo'}),
      );
      final c = await command();
      final state = await remote.readAnimalMoveState(c);
      state['paddocks'] = [
        {
          'id': 'B',
          'user_id': 'owner',
          'deleted_at': null,
          'status': 'En uso',
          'grazing_start_date': '2026-01-01T00:00:00Z',
          'planned_grazing_days': 4,
          'last_grazing_end_date': null,
        },
      ];
      await db.reconcileAnimalMoveSuccess(
        c,
        movement: await remote.pushAnimalMove(c),
        state: state,
      );
      final paddock = (await db.readRecord('paddocks', 'B'))!;
      expect(paddock.payload['name'], 'Nuevo');
      expect(paddock.payload['status'], 'En uso');
      expect(
        (await db.paddockPatches('owner')).single.payload['state'],
        'pending',
      );
    },
  );
  test(
    'server occupied rejection restores active paddock without DELETE ACK',
    () async {
      await db.markDeleted('paddocks', 'B', 'owner');
      await SyncRepositoryImpl(
        SyncLocalDataSource(db),
        OccupiedPaddockRemote(),
      ).pushPendingChanges();
      final p = (await db.readRecord('paddocks', 'B', includeDeleted: true))!;
      expect(p.isDeleted, false);
      expect(p.payload['name'], 'Remote');
      expect(
        SyncMetadata.read(p.payload)['deleteRejection'],
        'SYNC_PADDOCK_OCCUPIED',
      );
      expect(SyncMetadata.read(p.payload)['remoteOperationId'], isNull);
    },
  );
  for (final error in [
    (message: 'SYNC_MOVE_SOURCE_CONFLICT', code: 'P0001'),
    (message: 'SYNC_PADDOCK_OCCUPIED', code: '22023'),
  ]) {
    test(
      'paddock DELETE preserves pending for ${error.message}/${error.code}',
      () async {
        await db.markDeleted('paddocks', 'B', 'owner');
        final before = (await db.readRecord(
          'paddocks',
          'B',
          includeDeleted: true,
        ))!;
        final transport = OccupiedPaddockRemote()
          ..message = error.message
          ..code = error.code;
        await SyncRepositoryImpl(
          SyncLocalDataSource(db),
          transport,
        ).pushPendingChanges();
        final after = (await db.readRecord(
          'paddocks',
          'B',
          includeDeleted: true,
        ))!;
        expect(after.payload, before.payload);
        expect(SyncMetadata.read(after.payload)['deleteRejection'], isNull);
        expect(
          (await db.readPendingRecords()).any(
            (r) => r.collection == 'paddocks' && r.id == 'B',
          ),
          true,
        );
      },
    );
  }
  test(
    'pending operational paddock intent blocks MOVE but descriptive edit does not',
    () async {
      await db.applyPaddockPatch(
        'B',
        'owner',
        PaddockPatch({PaddockField.name: 'Name'}),
      );
      await enqueue();
      expect((await command()).payload['state'], 'pending');
    },
  );
  test('operational paddock patch cannot race a new MOVE command', () async {
    await db.applyPaddockPatch(
      'B',
      'owner',
      PaddockPatch({PaddockField.status: 'Descansando'}),
    );
    await expectLater(enqueue(), throwsStateError);
    expect(await db.animalMoveCommands('owner'), isEmpty);
    expect((await animal()).payload['_moveProjection'], isNull);
  });
}
