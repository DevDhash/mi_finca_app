import 'package:mi_finca_app/features/animals/domain/entities/animal_location_move_intent.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_patch.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_model.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';
import 'delete_a_test.dart' show DeleteTransport;

class AnimalTransport extends DeleteTransport
    implements AnimalPatchRemoteDataSource {
  final patches = <Map<String, Object?>>[];
  final full = <PendingRecord>[];
  Future<void> Function()? onPatch;
  @override
  Future<String?> animalVersion(String id, String owner) async => 'v1';
  @override
  Future<void> pushAnimalPatch(PendingRecord command) async {
    patches.add(
      AnimalPatch.fromLocal(
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
  late AppDatabase db;
  late Directory dir;
  final initial = <String, Object?>{
    'id': 'a',
    'code': 'A',
    'name': 'Luna',
    'type': 'Vaca',
    'breed': 'X',
    'sex': 'Hembra',
    'paddockId': 'B',
    'notes': '',
    'status': 'Activo',
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-01T00:00:00Z',
  };
  void open() => db = AppDatabase(NativeDatabase(File('${dir.path}/db')));
  Future<PendingRecord> row() async =>
      (await db.readRecord('animals', 'a', includeDeleted: true))!;
  Future<List<PendingRecord>> patches() =>
      db.animalPatches('owner', entityId: 'a');
  Future<void> edit(Map<AnimalField, Object?> fields) async {
    await db.applyAnimalPatch('a', 'owner', AnimalPatch(fields));
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('animal-patch');
    open();
    await db.writeSetting('session', jsonEncode({'id': 'owner'}));
    await db.putRecord(
      'animals',
      'a',
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
  test('name only patch preserves authoritative location C', () async {
    await db.putRecord(
      'animals',
      'a',
      {...initial, 'paddockId': 'C'},
      DateTime.utc(2026),
      pending: false,
      verifiedRemoteOwner: 'owner',
    );
    await edit({AnimalField.name: 'Luna II'});
    expect((await row()).payload['paddockId'], 'C');
    expect((await patches()).single.payload['fields'], {'name': 'Luna II'});
    expect((await db.readPendingRecords()).map((r) => r.collection), [
      animalPatchCollection,
    ]);
  });
  test('explicit null different from absent', () async {
    await edit({AnimalField.name: null});
    expect((await patches()).single.payload['fields'], {'name': null});
    expect((await row()).payload['breed'], 'X');
  });
  test('descriptive field has closed remote vocabulary', () {
    expect(AnimalPatch({AnimalField.weight: 45}).remoteValues, {'weight': 45});
    for (final field in [
      'paddockId',
      'paddock_id',
      'remotePhotoPath',
      'id',
      '_sync',
    ]) {
      expect(() => AnimalPatch.fromLocal({field: 'bad'}), throwsStateError);
    }
  });
  test('restart preserves order ownership and projection', () async {
    await edit({AnimalField.name: 'first'});
    await edit({AnimalField.name: 'second'});
    await db.close();
    open();
    final commands = await patches();
    expect(commands.length, 2);
    expect(commands.first.ownerId, 'owner');
    expect(
      commands.first.payload['order'],
      lessThan(commands.last.payload['order'] as int),
    );
    expect((await row()).payload['name'], 'second');
  });
  test('old ACK does not overwrite later local edit', () async {
    await edit({AnimalField.name: 'first'});
    final first = (await patches()).single;
    await edit({AnimalField.name: 'second'});
    await db.finishAnimalPatch(first);
    expect((await row()).payload['name'], 'second');
    expect((await patches()).last.payload['state'], 'pending');
  });
  test('patch sync sends only intended fields', () async {
    await edit({AnimalField.name: 'Luna II'});
    final remote = AnimalTransport();
    await SyncRepositoryImpl(
      SyncLocalDataSource(db),
      remote,
    ).pushPendingChanges();
    expect(remote.patches, [
      {'name': 'Luna II'},
    ]);
    expect(remote.full, isEmpty);
    expect((await patches()).single.payload['state'], 'completed');
  });
  test('MOVE projection and later patch independent', () async {
    await db.projectAnimalMove('a', 'owner', 'm1', 'C');
    expect(await db.readPendingRecords(), isEmpty);
    await edit({AnimalField.name: 'Luna II'});
    expect((await row()).payload['paddockId'], 'C');
    final remote = AnimalTransport();
    await SyncRepositoryImpl(
      SyncLocalDataSource(db),
      remote,
    ).pushPendingChanges();
    expect(remote.patches, [
      {'name': 'Luna II'},
    ]);
    expect(remote.full, isEmpty);
  });
  test('refresh merges remote location and photo with name overlay', () async {
    await edit({AnimalField.name: 'Luna II'});
    final local = AnimalLocalDataSource(db);
    final snap = await local.snapshotForRefresh('owner');
    await local.mergeRemoteAnimals([
      AnimalModel.fromJson({
        ...initial,
        'paddockId': 'C',
        'remotePhotoPath': 'remote',
      }),
    ], snap);
    expect((await row()).payload['name'], 'Luna II');
    expect((await row()).payload['paddockId'], 'C');
    expect((await row()).payload['remotePhotoPath'], 'remote');
    expect((await patches()).length, 1);
  });
  test('legacy quarantine preserves original payload without retry', () async {
    await db.putRecord('animals', 'a', {
      ...initial,
      'name': 'legacy',
    }, DateTime.utc(2026));
    final before = await row();
    final remote = AnimalTransport();
    await SyncRepositoryImpl(
      SyncLocalDataSource(db),
      remote,
    ).pushPendingChanges();
    await SyncRepositoryImpl(
      SyncLocalDataSource(db),
      remote,
    ).pushPendingChanges();
    expect(remote.full, isEmpty);
    expect(await db.readPendingRecords(), isEmpty);
    expect((await row()).payload['_legacyAnimalPayload'], before.payload);
    await db.close();
    open();
    expect(
      (await row()).payload['_animalConflict'],
      'LEGACY_LOCATION_AMBIGUOUS',
    );
    await expectLater(db.clearAll(), throwsA(isA<PendingSessionChanges>()));
  });
  test('owner isolation and logout protect unresolved patch', () async {
    await edit({AnimalField.notes: 'N'});
    await expectLater(
      db.beginSessionClose(),
      throwsA(isA<PendingSessionChanges>()),
    );
    await expectLater(db.animalPatches('other'), throwsStateError);
    await expectLater(
      db.applyAnimalPatch('a', 'other', AnimalPatch({AnimalField.name: 'bad'})),
      throwsStateError,
    );
  });
  test('terminal ledger defeats patches and move projection', () async {
    await db.projectAnimalMove('a', 'owner', 'm1', 'C');
    await edit({AnimalField.name: 'N'});
    await db.mergeRemoteTombstones('owner', [
      RemoteTombstone(
        collection: 'animals',
        id: 'a',
        ownerId: 'owner',
        operationId: 'delete',
        deletedAt: DateTime.utc(2026),
      ),
    ]);
    expect((await row()).isDeleted, true);
    expect((await patches()).single.payload['state'], 'conflict');
    await expectLater(edit({AnimalField.name: 'revive'}), throwsStateError);
    await db.putRecord(
      'animals',
      'a',
      initial,
      DateTime.utc(2026),
      pending: false,
      verifiedRemoteOwner: 'owner',
    );
    expect((await row()).isDeleted, true);
  });
  test(
    'explicit CREATE remains distinguishable and includes initial location',
    () async {
      final local = AnimalLocalDataSource(db);
      await local.save(AnimalModel.fromJson({...initial, 'id': 'new'}));
      final created = (await db.readRecord('animals', 'new'))!;
      expect(SyncMetadata.read(created.payload)['writeKind'], 'create');
      expect(created.payload['paddockId'], 'B');
      await local.save(AnimalModel.fromJson(initial));
      expect(
        SyncMetadata.read((await row()).payload)['writeKind'],
        'legacy_full_write',
      );
    },
  );
  test(
    'aborted form with copied photo creates no durable photo or edit intent',
    () async {
      final photo = File('${dir.path}/draft.jpg');
      await photo.writeAsBytes([1, 2, 3]);
      await expectLater(
        saveAnimalFormWithoutMove(
          locationIntent: const AnimalLocationMoveIntent(
            animalId: 'a',
            expectedFromPaddockId: 'B',
            toPaddockId: 'C',
          ),
          persist: () => AnimalLocalDataSource(db).edit(
            'a',
            AnimalPatch({AnimalField.name: 'new'}),
            selectedPhoto: photo.path,
          ),
        ),
        throwsA(isA<AnimalLocationMoveRequired>()),
      );
      expect(await db.readPendingRecords(), isEmpty);
      expect(await patches(), isEmpty);
      expect((await row()).payload['_photoUpload'], isNull);
      expect((await row()).payload['name'], 'Luna');
      expect(
        await photo.exists(),
        true,
      ); // unreferenced device file, no discovery source
    },
  );
  test(
    'pending photo and name survive refresh with authoritative location',
    () async {
      final local = AnimalLocalDataSource(db);
      await local.edit(
        'a',
        AnimalPatch({AnimalField.name: 'N'}),
        selectedPhoto: '/local/new.jpg',
      );
      final before = (await row()).payload['_photoUpload'];
      final snapshot = await local.snapshotForRefresh('owner');
      await local.mergeRemoteAnimals([
        AnimalModel.fromJson({...initial, 'paddockId': 'C'}),
      ], snapshot);
      expect((await row()).payload['paddockId'], 'C');
      expect((await row()).payload['name'], 'N');
      expect((await row()).payload['_photoUpload'], before);
      expect(SyncMetadata.read((await row()).payload)['writeKind'], 'photo');
    },
  );
  test(
    'legacy conflict cannot be overwritten by generic save or refreshed away',
    () async {
      await db.putRecord('animals', 'a', initial, DateTime.utc(2026));
      await db.quarantineLegacyAnimal(await row());
      await expectLater(
        db.putRecord('animals', 'a', {
          ...initial,
          'name': 'other',
        }, DateTime.utc(2026)),
        throwsStateError,
      );
      await db.putRecord(
        'animals',
        'a',
        {...initial, 'paddockId': 'C'},
        DateTime.utc(2026),
        pending: false,
        verifiedRemoteOwner: 'owner',
      );
      expect(
        (await row()).payload['_animalConflict'],
        'LEGACY_LOCATION_AMBIGUOUS',
      );
      expect((await row()).payload['_legacyAnimalPayload'], isNotNull);
    },
  );
  test(
    'unowned legacy is quarantined without guessing owner or probing network',
    () async {
      await db.customStatement(
        "INSERT INTO records(collection,id,payload,updated_at,pending) VALUES(?,?,?,?,?)",
        [
          'animals',
          'legacy',
          jsonEncode({...initial, 'id': 'legacy'}),
          DateTime.utc(2026).millisecondsSinceEpoch,
          1,
        ],
      );
      final remote = AnimalTransport();
      await SyncRepositoryImpl(
        SyncLocalDataSource(db),
        remote,
      ).pushPendingChanges();
      final legacy = (await db.readRecord('animals', 'legacy'))!;
      expect(legacy.ownerId, isNull);
      expect(legacy.payload['_animalConflict'], 'LEGACY_LOCATION_AMBIGUOUS');
      expect(remote.full, isEmpty);
      expect(await db.readPendingRecords(), isEmpty);
    },
  );
  test('photo selection cannot reclassify pending ambiguous legacy', () async {
    await db.putRecord('animals', 'a', {
      ...initial,
      'name': 'legacy',
    }, DateTime.utc(2026));
    final original = (await row()).payload;
    await expectLater(
      AnimalLocalDataSource(
        db,
      ).edit('a', AnimalPatch({}), selectedPhoto: '/new.jpg'),
      throwsStateError,
    );
    expect((await row()).payload, original);
  });
  test('conflict command cannot be acknowledged back to completed', () async {
    await edit({AnimalField.name: 'N'});
    await db.finishAnimalPatch(
      (await patches()).single,
      error: 'PATCH_VERSION_CONFLICT',
    );
    final conflict = (await patches()).single;
    expect(await db.finishAnimalPatch(conflict), false);
    expect((await patches()).single.payload['state'], 'conflict');
  });
  test(
    'GET started before patch ACK cannot restore stale descriptive state',
    () async {
      final local = AnimalLocalDataSource(db);
      await edit({AnimalField.name: 'N'});
      final snapshot = await local.snapshotForRefresh('owner');
      await db.finishAnimalPatch((await patches()).single);
      await local.mergeRemoteAnimals([AnimalModel.fromJson(initial)], snapshot);
      expect((await row()).payload['name'], 'N');
    },
  );
}
