import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_photo_storage.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_remote_datasource.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_photo_upload.dart';
import 'package:mi_finca_app/features/animals/data/repositories/animal_repository_impl.dart';
import 'package:mi_finca_app/features/animals/data/services/animal_photo_sync.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/usecases/move_animal.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PresenceRemote implements DeletionRemoteDataSource {
  @override
  String? currentUserId = 'owner';
  final physical = <String>{};
  final sent = <String>[];
  final reads = <String>[];
  final fail = <String>{};
  final ledger = <RemoteTombstone>[];
  Future<void> Function(PendingRecord)? duringPush;
  bool failRead = false;
  bool loseResponse = false;
  @override
  Future<bool> verifyLegacyOwner(PendingRecord record, String ownerId) async {
    reads.add('${record.collection}/${record.id}');
    if (failRead) throw const SocketException('read failed');
    return currentUserId == ownerId &&
        physical.contains('${record.collection}/${record.id}');
  }

  @override
  Future<void> pushRecord(PendingRecord record) async {
    final key = '${record.collection}/${record.id}';
    sent.add(key);
    await duringPush?.call(record);
    if (fail.contains(key)) throw const SocketException('failed');
    if (record.collection == 'movements') {
      expect(physical, contains('animals/${record.payload['animalId']}'));
      for (final field in ['fromPaddockId', 'toPaddockId']) {
        if (record.payload[field] != null) {
          expect(physical, contains('paddocks/${record.payload[field]}'));
        }
      }
    }
    physical.add(key);
    if (loseResponse) throw const SocketException('response lost');
  }

  @override
  Future<RemoteTombstone> softDelete(PendingRecord record) async {
    final result = RemoteTombstone(
      collection: record.collection,
      id: record.id,
      ownerId: record.ownerId!,
      operationId: record.operationId!,
      deletedAt: DateTime.utc(2030),
    );
    ledger.add(result);
    return result;
  }

  @override
  Future<List<RemoteTombstone>> fetchTombstones(String ownerId) async => ledger;
}

class PresenceStorage implements AnimalPhotoStorage {
  @override
  String? currentUserId = 'owner';
  int calls = 0;
  Future<void> Function()? onUpload;
  @override
  Future<void> ensureUploaded({
    required String ownerId,
    required String objectPath,
    required Uint8List bytes,
    required String digest,
    required String contentType,
  }) async {
    calls++;
    await onUpload?.call();
  }
}

class PresenceAnimals extends AnimalRemoteDataSource {
  PresenceAnimals(super.client);
  String? owner = 'owner';
  List<Animal> items = [];
  Future<void> Function()? duringRead;
  @override
  String? get currentUserId => owner;
  @override
  Future<List<Animal>> getAnimals() async {
    await duringRead?.call();
    return items;
  }
}

class AfterClaimLocal extends SyncLocalDataSource {
  AfterClaimLocal(super.database, this.afterClaim);
  final Future<void> Function() afterClaim;
  @override
  Future<PendingRecord?> beginRemotePublish(PendingRecord record) async {
    final claimed = await super.beginRemotePublish(record);
    await afterClaim();
    return claimed;
  }
}

void main() {
  late Directory directory;
  late AppDatabase db;
  late AnimalLocalDataSource local;
  late PresenceRemote remote;
  late PresenceStorage storage;
  late SyncRepositoryImpl sync;
  late SupabaseClient client;
  late PresenceAnimals reader;
  late AnimalRepositoryImpl repository;
  final date = DateTime.utc(2026);
  Animal animal({String name = 'Original', String? photo, String? paddock}) =>
      Animal(
        id: 'a',
        code: 'A',
        name: name,
        type: 'Vaca',
        breed: '',
        sex: 'Hembra',
        createdAt: date,
        updatedAt: date,
        localPhotoPath: photo,
        paddockId: paddock,
      );
  void connect() {
    db = AppDatabase(NativeDatabase(File('${directory.path}/store.sqlite')));
    local = AnimalLocalDataSource(db);
    sync = SyncRepositoryImpl(
      SyncLocalDataSource(db),
      remote,
      photos: AnimalPhotoSync(db, storage),
    );
    repository = AnimalRepositoryImpl(
      local: local,
      remote: reader,
      pullTombstones: sync.pullRemoteTombstones,
    );
  }

  Future<PendingRecord> row([
    String collection = 'animals',
    String id = 'a',
  ]) async => (await db.readRecord(collection, id, includeDeleted: true))!;
  Future<void> seed(
    String collection,
    String id, {
    Map<String, Object?>? fields,
    DateTime? at,
  }) => db.putRecord(collection, id, {'id': id, ...?fields}, at ?? date);
  Future<void> movement(String id, {DateTime? at}) => seed(
    'movements',
    id,
    fields: {'animalId': 'a', 'fromPaddockId': 'p1', 'toPaddockId': 'p2'},
    at: at ?? DateTime.utc(2000),
  );
  Future<void> family() async {
    await local.save(animal());
    await seed('paddocks', 'p1');
    await seed('paddocks', 'p2');
  }

  Future<void> legacy() async {
    await local.save(animal());
    final current = await row();
    final payload = {...current.payload}..remove('_sync');
    await db.customStatement(
      'UPDATE records SET payload = ? WHERE collection = ? AND id = ?',
      [jsonEncode(payload), 'animals', 'a'],
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('presence-c1');
    remote = PresenceRemote();
    storage = PresenceStorage();
    client = SupabaseClient('https://example.test', 'test');
    reader = PresenceAnimals(client);
    connect();
    await db.writeSetting('session', jsonEncode({'id': 'owner'}));
  });
  tearDown(() async {
    await db.close();
    await client.dispose();
    await directory.delete(recursive: true);
  });

  test('new animal is local_only; editing preserves it', () async {
    await local.save(animal());
    expect((await row()).remotePresence, RemotePresence.localOnly);
    await local.save(animal(name: 'Edit'));
    expect((await row()).remotePresence, RemotePresence.localOnly);
  });
  test(
    'legacy absent field is unknown and editing does not claim local origin',
    () async {
      await legacy();
      expect((await row()).remotePresence, RemotePresence.unknown);
      await local.save(animal(name: 'Edit'));
      expect((await row()).remotePresence, RemotePresence.unknown);
    },
  );
  test('confirmed survives edit and later publication claim', () async {
    await local.save(animal());
    await sync.pushPendingChanges();
    expect((await row()).remotePresence, RemotePresence.confirmed);
    await local.save(animal(name: 'Edit'));
    final claimed = await db.beginRemotePublish(await row());
    expect(claimed!.remotePresence, RemotePresence.confirmed);
  });
  test(
    'publication barrier persists unknown before network and restart',
    () async {
      await local.save(animal());
      await db.beginRemotePublish(await row());
      expect(remote.sent, isEmpty);
      await db.close();
      connect();
      expect((await row()).remotePresence, RemotePresence.unknown);
      await local.save(animal(name: 'After restart'));
      expect((await row()).remotePresence, RemotePresence.unknown);
    },
  );
  test(
    'first upsert sees unknown; positive response confirms and ACKs',
    () async {
      await local.save(animal());
      remote.duringPush = (_) async =>
          expect((await row()).remotePresence, RemotePresence.unknown);
      await sync.pushPendingChanges();
      expect((await row()).remotePresence, RemotePresence.confirmed);
      expect(await db.pendingCount(), 0);
    },
  );
  test(
    'late success confirms presence but preserves newer revision and operation',
    () async {
      await local.save(animal());
      PendingRecord? newer;
      remote.duringPush = (_) async {
        await local.save(animal(name: 'Newer'));
        newer = await row();
      };
      await sync.pushPendingChanges();
      final current = await row();
      expect(current.remotePresence, RemotePresence.confirmed);
      expect(current.payload['name'], 'Newer');
      expect(current.revision, newer!.revision);
      expect(current.operationId, newer!.operationId);
      expect(await db.pendingCount(), 1);
    },
  );
  test('lost response remains unknown despite physical server row', () async {
    await local.save(animal());
    remote.loseResponse = true;
    await sync.pushPendingChanges();
    expect(remote.physical, contains('animals/a'));
    expect((await row()).remotePresence, RemotePresence.unknown);
    expect(await db.pendingCount(), 1);
  });
  test(
    'refresh positive records evidence without replacing pending edit',
    () async {
      await local.save(animal(name: 'Local'));
      await db.beginRemotePublish(await row());
      final before = await row();
      reader.items = [animal(name: 'Remote')];
      await repository.refreshAnimals();
      final current = await row();
      expect(current.remotePresence, RemotePresence.confirmed);
      expect(current.payload['name'], 'Local');
      expect(current.revision, before.revision);
      expect(current.operationId, before.operationId);
      expect(await db.pendingCount(), 1);
    },
  );
  test('empty refresh does not infer absence or confirmation', () async {
    await legacy();
    await repository.refreshAnimals();
    expect((await row()).remotePresence, RemotePresence.unknown);
  });
  test('account switch during refresh rejects evidence', () async {
    await local.save(animal());
    reader.items = [animal()];
    reader.duringRead = () async {
      reader.owner = 'other';
      await db.writeSetting('session', jsonEncode({'id': 'other'}));
    };
    await expectLater(repository.refreshAnimals(), throwsStateError);
    expect((await row()).remotePresence, RemotePresence.localOnly);
  });
  test('account switch during upsert cannot confirm or ACK', () async {
    await local.save(animal());
    remote.duringPush = (_) async {
      remote.currentUserId = 'other';
      storage.currentUserId = 'other';
      await db.writeSetting('session', jsonEncode({'id': 'other'}));
    };
    await sync.pushPendingChanges();
    expect((await row()).remotePresence, RemotePresence.unknown);
    expect(await db.pendingCount(), 1);
  });
  test('stale claim after newer edit is rejected before request', () async {
    await local.save(animal());
    final old = await row();
    await local.save(animal(name: 'New'));
    expect(await db.beginRemotePublish(old), isNull);
    expect((await row()).remotePresence, RemotePresence.localOnly);
  });
  test(
    'terminal row rejects publication claim and remains physically local',
    () async {
      await local.save(animal());
      final old = await row();
      await db.markDeleted('animals', 'a', 'owner');
      expect(await db.beginRemotePublish(old), isNull);
      expect((await row()).isDeleted, true);
      expect(remote.sent, isEmpty);
    },
  );
  test(
    'old successful response adds evidence without removing newer tombstone',
    () async {
      await local.save(animal());
      remote.duringPush = (_) => db.markDeleted('animals', 'a', 'owner');
      await sync.pushPendingChanges();
      expect((await row()).isDeleted, true);
      expect((await row()).remotePresence, RemotePresence.confirmed);
      expect(await db.pendingCount(), 1);
    },
  );
  test('ledger alone does not confirm physical existence', () async {
    await local.save(animal());
    remote.ledger.add(
      RemoteTombstone(
        collection: 'animals',
        id: 'a',
        ownerId: 'owner',
        operationId: 'remote-delete',
        deletedAt: date,
      ),
    );
    await sync.pullRemoteTombstones();
    expect((await row()).remotePresence, isNot(RemotePresence.confirmed));
    expect((await row()).isDeleted, true);
  });
  test('confirmed evidence survives restart and remote tombstone', () async {
    await local.save(animal());
    await sync.pushPendingChanges();
    await db.close();
    connect();
    await db.markDeleted('animals', 'a', 'owner');
    await sync.pushPendingChanges();
    expect((await row()).remotePresence, RemotePresence.confirmed);
    expect((await row()).isDeleted, true);
    expect(await db.pendingCount(), 0);
  });
  for (final field in ['animal', 'from paddock', 'to paddock']) {
    test(
      'movement waits for LOCAL_ONLY $field with adverse timestamps',
      () async {
        await family();
        await movement('m');
        await sync.pushPendingChanges();
        final parent = field == 'animal'
            ? 'animals/a'
            : field == 'from paddock'
            ? 'paddocks/p1'
            : 'paddocks/p2';
        expect(
          remote.sent.indexOf(parent),
          lessThan(remote.sent.indexOf('movements/m')),
        );
        expect(await db.pendingCount(), 0);
      },
    );
  }
  test('equal timestamps still respect all movement dependencies', () async {
    await movement('m', at: date);
    await family();
    await sync.pushPendingChanges();
    expect(remote.sent.last, 'movements/m');
    expect(await db.pendingCount(), 0);
  });
  test(
    'parent failure defers multiple children without blocking independent expense',
    () async {
      await family();
      await movement('m1');
      await movement('m2');
      await seed('expenses', 'e');
      remote.fail.add('animals/a');
      await sync.pushPendingChanges();
      expect(remote.sent.where((e) => e == 'animals/a'), hasLength(1));
      expect(remote.sent.any((e) => e.startsWith('movements/')), false);
      expect(remote.sent, contains('expenses/e'));
      expect(await db.pendingCount(), 3);
      remote.fail.clear();
      await sync.pushPendingChanges();
      expect(await db.pendingCount(), 0);
    },
  );
  test(
    'confirmed parent with pending failed edit still permits historical child',
    () async {
      await family();
      await sync.pushPendingChanges();
      await local.save(animal(name: 'Edit'));
      await movement('m');
      remote.fail.add('animals/a');
      await sync.pushPendingChanges();
      expect(remote.sent, contains('movements/m'));
      expect(await db.pendingCount(), 1);
    },
  );
  test(
    'confirmed soft-deleted parent permits pending historical movement',
    () async {
      await family();
      await sync.pushPendingChanges();
      await db.markDeleted('animals', 'a', 'owner');
      await sync.pushPendingChanges();
      await movement('m');
      await sync.pushPendingChanges();
      expect(remote.sent, contains('movements/m'));
      expect((await row()).isDeleted, true);
      expect(await db.pendingCount(), 0);
    },
  );
  test(
    'unknown parent positive lookup confirms without forcing its pending edit',
    () async {
      await family();
      await db.beginRemotePublish(await row());
      remote.physical.add('animals/a');
      await movement('m');
      remote.fail.add('animals/a');
      await sync.pushPendingChanges();
      expect((await row()).remotePresence, RemotePresence.confirmed);
      expect(remote.sent, contains('movements/m'));
    },
  );
  test(
    'missing unknown parent defers rather than manufacturing a row',
    () async {
      await seed('movements', 'm', fields: {'animalId': 'missing'});
      await sync.pushPendingChanges();
      expect(remote.sent, isEmpty);
      expect(await db.pendingCount(), 1);
    },
  );
  test(
    'unknown parent lookup error preserves pending and allows independent work',
    () async {
      await seed('movements', 'm', fields: {'animalId': 'missing'});
      await seed('expenses', 'e');
      remote.failRead = true;
      await sync.pushPendingChanges();
      expect(remote.sent, ['expenses/e']);
      expect(await db.pendingCount(), 1);
    },
  );
  test('legacy ownership by positive row read confirms existence', () async {
    await legacy();
    remote.physical.add('animals/a');
    expect(await sync.verifyLegacyOwnership('animals', 'a', 'owner'), true);
    expect((await row()).remotePresence, RemotePresence.confirmed);
  });
  test('local owner evidence alone never confirms existence', () async {
    await local.save(animal());
    expect(await sync.verifyLegacyOwnership('animals', 'a', 'owner'), true);
    expect((await row()).remotePresence, RemotePresence.localOnly);
  });
  test('legacy no positive row read stays unknown', () async {
    await legacy();
    expect(await sync.verifyLegacyOwnership('animals', 'a', 'owner'), false);
    expect((await row()).remotePresence, RemotePresence.unknown);
  });
  test(
    'original scenario: real move usecase multiple offline moves and restart',
    () async {
      await family();
      final mover = MoveAnimal(repository);
      final first = await mover(
        animal(paddock: 'p1'),
        'p2',
        DateTime.utc(2000),
      );
      await mover(first.animal, 'p1', DateTime.utc(2001));
      await db.close();
      connect();
      await sync.pushPendingChanges();
      final animalIndex = remote.sent.indexOf('animals/a');
      final moves = remote.sent.where((e) => e.startsWith('movements/'));
      expect(moves, hasLength(2));
      for (final move in moves) {
        expect(remote.sent.indexOf(move), greaterThan(animalIndex));
      }
      expect(await db.pendingCount(), 0);
    },
  );
  test(
    'photo upload starts unknown, Storage does not confirm; publish does',
    () async {
      final file = File('${directory.path}/photo.png');
      await file.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10, 1]);
      await family();
      await local.save(animal(photo: file.path));
      await movement('m');
      storage.onUpload = () async {
        expect((await row()).remotePresence, RemotePresence.unknown);
        expect(remote.physical.contains('animals/a'), false);
      };
      remote.duringPush = (r) async {
        if (r.collection == 'animals') {
          expect((await row()).remotePresence, RemotePresence.unknown);
          expect(
            AnimalPhotoUpload.read((await row()).payload)!['status'],
            'uploaded',
          );
        }
      };
      await sync.pushPendingChanges();
      expect(storage.calls, 1);
      expect((await row()).remotePresence, RemotePresence.confirmed);
      expect(
        AnimalPhotoUpload.read((await row()).payload)!['status'],
        'published',
      );
      expect(
        remote.sent.indexOf('animals/a'),
        lessThan(remote.sent.indexOf('movements/m')),
      );
      expect(await file.exists(), true);
      expect(await db.pendingCount(), 0);
    },
  );
  test(
    'Storage success with failed animal publication stays unknown across restart',
    () async {
      final file = File('${directory.path}/photo.png');
      await file.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10, 1]);
      await local.save(animal(photo: file.path));
      remote.fail.add('animals/a');
      await sync.pushPendingChanges();
      expect((await row()).payload['remotePhotoPath'], isNotNull);
      expect((await row()).remotePresence, RemotePresence.unknown);
      await db.close();
      connect();
      remote.fail.clear();
      await sync.pushPendingChanges();
      expect(storage.calls, 1);
      expect((await row()).remotePresence, RemotePresence.confirmed);
      expect(await file.exists(), true);
    },
  );
  test(
    'concurrent sync shares one publication and confirms all dependencies',
    () async {
      await family();
      await movement('m');
      await Future.wait([sync.pushPendingChanges(), sync.pushPendingChanges()]);
      expect(remote.sent.toSet().length, remote.sent.length);
      expect(await db.pendingCount(), 0);
    },
  );
  test(
    'generic ACK confirms existence without consuming a newer paddock edit',
    () async {
      await seed('paddocks', 'p');
      PendingRecord? newer;
      remote.duringPush = (_) async {
        await seed('paddocks', 'p', fields: {'name': 'new'});
        newer = await row('paddocks', 'p');
      };
      await sync.pushPendingChanges();
      final current = await row('paddocks', 'p');
      expect(current.remotePresence, RemotePresence.confirmed);
      expect(current.operationId, newer!.operationId);
      expect(current.revision, newer!.revision);
      expect(current.payload['name'], 'new');
      expect(await db.pendingCount(), 1);
    },
  );
  test(
    'photo owner evidence verifies legacy ownership but not physical presence',
    () async {
      await legacy();
      final current = await row();
      final payload = {
        ...current.payload,
        '_photoUpload': {'ownerId': 'owner'},
      };
      await db.customStatement(
        'UPDATE records SET payload = ? WHERE collection = ? AND id = ?',
        [jsonEncode(payload), 'animals', 'a'],
      );
      expect(await sync.verifyLegacyOwnership('animals', 'a', 'owner'), true);
      expect((await row()).remotePresence, RemotePresence.unknown);
      expect(remote.physical, isEmpty);
    },
  );
  test(
    'refresh of clean legacy row updates content and confirms presence',
    () async {
      await legacy();
      await db.markRecordSynced('animals', 'a');
      reader.items = [animal(name: 'Remote')];
      await repository.refreshAnimals();
      expect((await row()).payload['name'], 'Remote');
      expect((await row()).remotePresence, RemotePresence.confirmed);
      expect(await db.pendingCount(), 0);
    },
  );
  test(
    'confirmed parent evidence cannot be reassigned to another owner',
    () async {
      await local.save(animal());
      await sync.pushPendingChanges();
      await db.writeSetting('session', jsonEncode({'id': 'other'}));
      await expectLater(
        db.markRemoteConfirmed('animals', 'a', 'other'),
        throwsStateError,
      );
      expect((await row()).ownerId, 'owner');
      expect((await row()).remotePresence, RemotePresence.confirmed);
    },
  );
  test(
    'refresh evidence during photo upload survives checkpoints and final ACK',
    () async {
      final file = File('${directory.path}/photo.png');
      await file.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10, 1]);
      await local.save(animal(photo: file.path));
      storage.onUpload = () async {
        reader.items = [animal(name: 'old remote')];
        await repository.refreshAnimals();
        expect((await row()).remotePresence, RemotePresence.confirmed);
      };
      await sync.pushPendingChanges();
      expect((await row()).remotePresence, RemotePresence.confirmed);
      expect((await row()).payload['name'], 'Original');
      expect(
        AnimalPhotoUpload.read((await row()).payload)!['status'],
        'published',
      );
      expect(await db.pendingCount(), 0);
    },
  );
  test(
    'operation is revalidated after durable claim before dispatch',
    () async {
      await seed('paddocks', 'p');
      final worker = SyncRepositoryImpl(
        AfterClaimLocal(db, () async {
          await seed('paddocks', 'p', fields: {'name': 'new after claim'});
        }),
        remote,
      );
      await worker.pushPendingChanges();
      expect(remote.sent, isEmpty);
      expect(
        (await row('paddocks', 'p')).remotePresence,
        RemotePresence.unknown,
      );
      expect((await row('paddocks', 'p')).payload['name'], 'new after claim');
      expect(await db.pendingCount(), 1);
    },
  );
  test('sameOperation ignores map insertion order and only remotePresence', () {
    final a = <String, Object?>{
      'id': 'a',
      'nested': {
        'x': 1,
        'y': [1, 2],
      },
      '_sync': {
        'ownerId': 'owner',
        'revision': 2,
        'operationId': 'op',
        'remotePresence': 'unknown',
      },
    };
    final b = <String, Object?>{
      '_sync': {
        'remotePresence': 'confirmed',
        'operationId': 'op',
        'revision': 2,
        'ownerId': 'owner',
      },
      'nested': {
        'y': [1, 2],
        'x': 1,
      },
      'id': 'a',
    };
    expect(SyncMetadata.sameOperation(a, b), true);
    for (final change in <String, Object?>{
      'ownerId': 'other',
      'revision': 3,
      'operationId': 'new',
      'operation': 'delete',
      'tombstone': true,
      'requestedAt': 'different',
      'ownership': 'different',
    }.entries) {
      final changed = {
        ...b,
        '_sync': {...SyncMetadata.read(b), change.key: change.value},
      };
      expect(SyncMetadata.sameOperation(a, changed), false, reason: change.key);
    }
    expect(
      SyncMetadata.sameOperation(a, {
        ...b,
        'nested': {
          'x': 1,
          'y': [2, 1],
        },
      }),
      false,
    );
  });
  for (final initial in ['absent', 'unknown', 'pending', 'confirmed']) {
    test('putRecord verifiedRemoteOwner is atomic for $initial', () async {
      if (initial != 'absent') {
        await legacy();
        await local.save(animal(name: 'Local'));
        if (initial != 'pending') await db.markRecordSynced('animals', 'a');
        if (initial == 'confirmed') {
          await db.markRemoteConfirmed('animals', 'a', 'owner');
        }
      }
      final before = await db.readRecord('animals', 'a');
      final payload = before?.payload ?? {'id': 'a'};
      await db.putRecord(
        'animals',
        'a',
        {...payload, 'name': 'Remote'},
        date,
        pending: false,
        verifiedRemoteOwner: 'owner',
      );
      final current = await row();
      expect(current.remotePresence, RemotePresence.confirmed);
      expect(current.ownerId, 'owner');
      expect(await db.pendingCount(), initial == 'pending' ? 1 : 0);
      if (initial == 'pending') {
        expect(current.payload['name'], 'Local');
        expect(current.operationId, before!.operationId);
        expect(current.revision, before.revision);
      } else {
        expect(current.payload['name'], 'Remote');
      }
    });
  }
  test(
    'putRecord rolls back positive evidence when subsequent write fails',
    () async {
      await legacy();
      await db.markRecordSynced('animals', 'a');
      final before = await row();
      await expectLater(
        db.putRecord(
          'animals',
          'a',
          {'id': 'a', 'invalidJson': Object()},
          date,
          pending: false,
          verifiedRemoteOwner: 'owner',
        ),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect((await row()).payload, before.payload);
      expect(await db.pendingCount(), 0);
    },
  );
  for (final newParent in ['animal', 'paddock']) {
    test(
      'siblings share one $newParent publication and progress in the same pass',
      () async {
        await family();
        if (newParent == 'animal') {
          for (final id in ['p1', 'p2']) {
            remote.physical.add('paddocks/$id');
            await db.markRemoteConfirmed('paddocks', id, 'owner');
            await db.markRecordSynced('paddocks', id);
          }
        } else {
          remote.physical.add('animals/a');
          await db.markRemoteConfirmed('animals', 'a', 'owner');
          await db.markRecordSynced('animals', 'a');
        }
        await movement('m1');
        await movement('m2');
        await sync.pushPendingChanges();
        expect(await db.pendingCount(), 0);
        expect(
          remote.sent.where((e) => e.startsWith('movements/')),
          hasLength(2),
        );
        for (final key in remote.sent.toSet()) {
          expect(remote.sent.where((e) => e == key), hasLength(1));
        }
      },
    );
  }
  test(
    'cached false cannot hide parent confirmed later in the same sync pass',
    () async {
      await local.save(animal());
      await db.beginRemotePublish(await row());
      await seed(
        'movements',
        'm1',
        at: DateTime.utc(2000),
        fields: {'animalId': 'a'},
      );
      await seed('expenses', 'e', at: DateTime.utc(2001));
      await seed(
        'movements',
        'm2',
        at: DateTime.utc(2002),
        fields: {'animalId': 'a'},
      );
      remote.failRead = true;
      remote.duringPush = (record) async {
        if (record.collection == 'expenses') {
          remote.failRead = false;
          remote.physical.add('animals/a');
          reader.items = [animal()];
          await repository.refreshAnimals();
        }
      };
      await sync.pushPendingChanges();
      expect(remote.sent, contains('movements/m2'));
      expect(remote.sent, isNot(contains('movements/m1')));
      expect(await db.pendingCount(), 1);
    },
  );
  test(
    'ambiguous parent response does not cause repeated publish for siblings',
    () async {
      await local.save(animal());
      for (final id in ['m1', 'm2', 'm3']) {
        await seed(
          'movements',
          id,
          at: DateTime.utc(2000),
          fields: {'animalId': 'a'},
        );
      }
      remote.loseResponse = true;
      await sync.pushPendingChanges();
      expect(remote.sent, ['animals/a']);
      expect((await row()).remotePresence, RemotePresence.unknown);
      expect(await db.pendingCount(), 4);
    },
  );
  test('siblings reuse positive parent read without publishing it', () async {
    await local.save(animal());
    await db.beginRemotePublish(await row());
    await db.markRecordSynced('animals', 'a');
    remote.physical.add('animals/a');
    for (final id in ['m1', 'm2', 'm3']) {
      await seed('movements', id, fields: {'animalId': 'a'});
    }
    await sync.pushPendingChanges();
    expect(remote.reads.where((e) => e == 'animals/a'), hasLength(1));
    expect(remote.sent.where((e) => e == 'animals/a'), isEmpty);
    expect(remote.sent, hasLength(3));
    expect(await db.pendingCount(), 0);
  });
  for (final presence in RemotePresence.values) {
    test(
      'markDeleted preserves ${presence.name} without local cancellation',
      () async {
        await local.save(animal());
        if (presence == RemotePresence.unknown) {
          await db.beginRemotePublish(await row());
        }
        if (presence == RemotePresence.confirmed) {
          await db.markRemoteConfirmed('animals', 'a', 'owner');
        }
        await db.markDeleted('animals', 'a', 'owner');
        expect((await row()).remotePresence, presence);
        expect((await row()).operation, 'delete');
        expect((await row()).isDeleted, true);
        expect(await db.pendingCount(), 1);
        expect(remote.ledger, isEmpty);
      },
    );
  }
  test(
    'revision one evidence and ACK cannot alter revision two or its later DELETE',
    () async {
      await local.save(animal());
      final first = (await db.beginRemotePublish(await row()))!;
      await local.save(animal(name: 'Revision two'));
      final second = await row();
      await db.markRemoteConfirmed('animals', 'a', 'owner');
      final confirmed = await row();
      expect(confirmed.operationId, second.operationId);
      expect(confirmed.revision, second.revision);
      expect(
        SyncMetadata.sameOperation(confirmed.payload, second.payload),
        true,
      );
      expect(
        await db.replaceRecordIfUnchanged(first, first.payload, pending: false),
        false,
      );
      await db.markDeleted('animals', 'a', 'owner');
      final deleted = await row();
      await db.markRemoteConfirmed('animals', 'a', 'owner');
      expect(
        await db.replaceRecordIfUnchanged(first, first.payload, pending: false),
        false,
      );
      expect((await row()).payload, deleted.payload);
      expect(await db.pendingCount(), 1);
    },
  );
  test(
    'session changes after remote result but before evidence merge',
    () async {
      await local.save(animal());
      await db.beginRemotePublish(await row());
      remote.physical.add('animals/a'); // Positive response for owner A.
      final before = await row();
      await db.writeSetting('session', jsonEncode({'id': 'B'}));
      await expectLater(
        db.markRemoteConfirmed('animals', 'a', 'owner'),
        throwsStateError,
      );
      expect((await row()).payload, before.payload);
      expect(await db.pendingCount(), 1);
    },
  );
  test(
    'late refresh from A cannot confirm a replacement row belonging to B',
    () async {
      await local.save(animal());
      reader.items = [animal(name: 'Response A')];
      reader.duringRead = () async {
        await db.clearAll();
        await db.writeSetting('session', jsonEncode({'id': 'B'}));
        reader.owner = 'B';
        await local.save(animal(name: 'Local B'));
      };
      await expectLater(repository.refreshAnimals(), throwsStateError);
      final current = await row();
      expect(current.ownerId, 'B');
      expect(current.payload['name'], 'Local B');
      expect(current.remotePresence, RemotePresence.localOnly);
      expect(await db.pendingCount(), 1);
    },
  );
}
