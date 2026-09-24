import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_photo_storage.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_model.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_photo_upload.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_remote_payload.dart';
import 'package:mi_finca_app/features/animals/data/services/animal_photo_sync.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';

void main() {
  late Directory directory;
  late File photo;
  late AppDatabase database;
  late AnimalLocalDataSource local;
  late FakeStorage storage;
  late FakeRemote remote;
  late SyncRepositoryImpl sync;

  void connect() {
    database = AppDatabase(NativeDatabase(File('${directory.path}/db.sqlite')));
    local = AnimalLocalDataSource(database);
    sync = SyncRepositoryImpl(
      SyncLocalDataSource(database),
      remote,
      photos: AnimalPhotoSync(database, storage),
    );
  }

  Animal animal({String? path}) => Animal(
    id: 'animal',
    code: 'A-1',
    type: 'Vaca',
    breed: '',
    sex: 'Hembra',
    localPhotoPath: path ?? photo.path,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  Future<PendingRecord> saved() async =>
      (await database.readRecord('animals', 'animal'))!;
  Future<Map<String, Object?>> job() async =>
      AnimalPhotoUpload.read((await saved()).payload)!;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('foto-b-test');
    photo = File('${directory.path}/photo.png')
      ..writeAsBytesSync([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]);
    storage = FakeStorage();
    remote = FakeRemote();
    connect();
    await database.writeSetting('session', jsonEncode({'id': 'user'}));
  });
  tearDown(() async {
    await database.close();
    directory.deleteSync(recursive: true);
  });

  test(
    'saving offline persists owner/version without contacting Storage',
    () async {
      await local.save(animal());
      expect((await job())['ownerId'], 'user');
      expect((await job())['status'], 'pending');
      expect((await job())['version'], isNotEmpty);
      expect(storage.calls, 0);
      expect(await sync.pendingCount(), 1);
      expect(photo.existsSync(), isTrue);
    },
  );

  test(
    'upload timeout preserves intent and late completion can be retried',
    () async {
      await local.save(animal());
      final gate = Completer<void>();
      storage.beforeUpload = () => gate.future;
      final coordinator = AnimalPhotoSync(
        database,
        storage,
        uploadTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        coordinator.push(await saved(), remote.pushRecord),
        throwsA(isA<TimeoutException>()),
      );
      final target = (await job())['target'];
      expect(target, isNotNull);
      expect(await database.pendingCount(), 1);
      expect(photo.existsSync(), true);
      expect(remote.payloads, isEmpty);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      storage.beforeUpload = null;
      await sync.pushPendingChanges();
      expect(await database.pendingCount(), 0);
      expect((await job())['target'], target);
      expect(storage.objects, hasLength(1));
    },
  );

  test('upload precedes publication; only remote path leaves device', () async {
    await local.save(animal());
    remote.beforePush = (_) async => expect(storage.objects, hasLength(1));
    await sync.pushPendingChanges();
    final payload = (await saved()).payload;
    expect(payload['remotePhotoPath'], storage.objects.keys.single);
    expect(payload['localPhotoPath'], photo.path);
    expect((await job())['status'], 'published');
    expect(await sync.pendingCount(), 0);
    expect(
      remote.payloads.single['remote_photo_path'],
      payload['remotePhotoPath'],
    );
    expect(remote.payloads.single.keys, isNot(contains('localPhotoPath')));
    expect(remote.payloads.single.keys, isNot(contains('_photoUpload')));
    expect(photo.existsSync(), isTrue);
  });

  test(
    'upload failure preserves file, destination, pending and old reference',
    () async {
      const previous = 'user/animal/550e8400-e29b-41d4-a716-446655440000.jpg';
      await local.save(animal().copyWith(remotePhotoPath: previous));
      storage.fail = true;
      await sync.pushPendingChanges();
      final target = (await job())['target'];
      expect(target, isNotNull);
      expect((await saved()).payload['remotePhotoPath'], previous);
      expect((await job())['lastError'], 'upload_or_sync_failed');
      expect(await sync.pendingCount(), 1);
      expect(remote.payloads, isEmpty);
      expect(photo.existsSync(), isTrue);
      storage.fail = false;
      await sync.pushPendingChanges();
      expect(storage.objects.keys.single, target);
      expect(await sync.pendingCount(), 0);
    },
  );

  test('other outbox records progress when a photo fails', () async {
    await local.save(animal());
    await database.putRecord('expenses', 'expense', {
      'id': 'expense',
    }, DateTime(2026));
    storage.fail = true;
    await sync.pushPendingChanges();
    expect(remote.collections, ['expenses']);
    expect(await sync.pendingCount(), 1);
  });

  test(
    'restart after upload retries publication even if local file disappears',
    () async {
      await local.save(animal());
      remote.fail = true;
      await sync.pushPendingChanges();
      expect((await job())['status'], 'uploaded');
      final path = (await saved()).payload['remotePhotoPath'];
      expect(await sync.pendingCount(), 1);
      await database.close();
      connect();
      photo.deleteSync();
      remote.fail = false;
      await sync.pushPendingChanges();
      expect(storage.calls, 1);
      expect((await saved()).payload['remotePhotoPath'], path);
      expect(await sync.pendingCount(), 0);
    },
  );

  test(
    'lost upload response reuses durable destination after restart',
    () async {
      await local.save(animal());
      storage.loseResponse = true;
      await sync.pushPendingChanges();
      final target = (await job())['target'];
      expect((await job())['status'], 'pending');
      await database.close();
      connect();
      storage.loseResponse = false;
      await sync.pushPendingChanges();
      expect(storage.calls, 2);
      expect(storage.objects, hasLength(1));
      expect((await saved()).payload['remotePhotoPath'], target);
      expect(await sync.pendingCount(), 0);
    },
  );

  test(
    'replacement during upload cannot publish or acknowledge the old photo',
    () async {
      await local.save(animal());
      final entered = Completer<void>();
      final release = Completer<void>();
      storage.beforeUpload = () async {
        entered.complete();
        await release.future;
      };
      final active = sync.pushPendingChanges();
      await entered.future;
      final next = File('${directory.path}/next.png')
        ..writeAsBytesSync([137, 80, 78, 71, 13, 10, 26, 10, 4, 5]);
      await local.save(animal(path: next.path));
      final newVersion = (await job())['version'];
      release.complete();
      await active;
      expect((await job())['version'], newVersion);
      expect((await job())['status'], 'pending');
      expect(remote.payloads, isEmpty);
      expect(await sync.pendingCount(), 1);
      storage.beforeUpload = null;
      await sync.pushPendingChanges();
      expect((await saved()).payload['remotePhotoPath'], contains(newVersion));
      expect(await sync.pendingCount(), 0);
    },
  );

  test(
    'edit during publication stays pending and preserves uploaded reference',
    () async {
      final staleAnimal = animal();
      await local.save(staleAnimal);
      remote.beforePush = (_) async {
        remote.beforePush = null;
        await local.save(staleAnimal.copyWith(code: 'A-2'));
      };
      await sync.pushPendingChanges();
      expect(await sync.pendingCount(), 1);
      expect((await saved()).payload['code'], 'A-2');
      expect((await saved()).payload['remotePhotoPath'], isNotNull);
      await sync.pushPendingChanges();
      expect(storage.calls, 1);
      expect(remote.payloads.last['code'], 'A-2');
      expect(await sync.pendingCount(), 0);
    },
  );

  test('simultaneous sync requests share one worker', () async {
    await local.save(animal());
    await Future.wait([sync.pushPendingChanges(), sync.pushPendingChanges()]);
    expect(storage.calls, 1);
    expect(remote.payloads, hasLength(1));
  });

  test(
    'FOTO A synced local photos are enrolled without reading remote legacy paths',
    () async {
      final legacy = AnimalModel.toJson(animal())
        ..remove('localPhotoPath')
        ..['photoPath'] = photo.path;
      await database.putRecord(
        'animals',
        'animal',
        legacy,
        DateTime(2026),
        pending: false,
      );
      expect(await sync.pendingCount(), 1);
      await sync.pushPendingChanges();
      expect((await saved()).payload['remotePhotoPath'], isNotNull);
      expect(await sync.pendingCount(), 0);
    },
  );

  test(
    'remote reference without an upload intent is not uploaded again',
    () async {
      await local.save(
        animal().copyWith(
          remotePhotoPath:
              'user/animal/550e8400-e29b-41d4-a716-446655440000.jpg',
        ),
        pending: false,
      );
      expect(await sync.pendingCount(), 0);
      await sync.pushPendingChanges();
      expect(storage.calls, 0);
    },
  );

  test('missing local file retains a recoverable pending error', () async {
    await local.save(animal());
    photo.deleteSync();
    await sync.pushPendingChanges();
    expect((await job())['lastError'], 'missing_file');
    expect(await sync.pendingCount(), 1);
    expect(storage.calls, 0);
    expect(remote.payloads, isEmpty);
  });

  test(
    'file mutation after a failed attempt cannot reuse the old destination',
    () async {
      await local.save(animal());
      storage.fail = true;
      await sync.pushPendingChanges();
      photo.writeAsBytesSync([137, 80, 78, 71, 13, 10, 26, 10, 99]);
      storage.fail = false;
      await sync.pushPendingChanges();
      expect((await job())['lastError'], 'local_file_changed');
      expect(storage.calls, 1);
      expect(await sync.pendingCount(), 1);
    },
  );

  for (final owner in [null, 'another-user']) {
    test(
      'session $owner cannot upload or publish another owner intent',
      () async {
        await local.save(animal());
        storage.currentUserId = owner;
        await sync.pushPendingChanges();
        expect((await job())['lastError'], 'auth_required');
        expect(storage.calls, 0);
        expect(remote.payloads, isEmpty);
        expect(await sync.pendingCount(), 1);
      },
    );
  }

  test('session change during upload prevents publication', () async {
    await local.save(animal());
    storage.beforeUpload = () async => storage.currentUserId = 'another-user';
    await sync.pushPendingChanges();
    expect(remote.payloads, isEmpty);
    expect(await sync.pendingCount(), 1);
    expect((await job())['ownerId'], 'user');
  });

  test(
    'cleared database cannot be resurrected by an upload response',
    () async {
      await local.save(animal());
      storage.beforeUpload = database.clearAll;
      await sync.pushPendingChanges();
      expect(await database.readRecords('animals'), isEmpty);
      expect(remote.payloads, isEmpty);
    },
  );
}

class FakeStorage implements AnimalPhotoStorage {
  @override
  String? currentUserId = 'user';
  bool fail = false;
  bool loseResponse = false;
  int calls = 0;
  final objects = <String, String>{};
  Future<void> Function()? beforeUpload;

  @override
  Future<void> ensureUploaded({
    required String ownerId,
    required String objectPath,
    required Uint8List bytes,
    required String digest,
    required String contentType,
  }) async {
    calls++;
    await beforeUpload?.call();
    if (fail) throw const SocketException('offline');
    if (objects.containsKey(objectPath)) {
      expect(objects[objectPath], digest);
    }
    objects[objectPath] = digest;
    if (loseResponse) throw const SocketException('response lost');
  }
}

class FakeRemote implements SyncRemoteDataSource {
  bool fail = false;
  final payloads = <Map<String, Object?>>[];
  final collections = <String>[];
  Future<void> Function(PendingRecord)? beforePush;

  @override
  Future<void> pushRecord(PendingRecord record) async {
    await beforePush?.call(record);
    if (fail) throw const SocketException('publication failed');
    collections.add(record.collection);
    payloads.add(
      record.collection == 'animals'
          ? AnimalRemotePayload.fromLocal(record.payload, 'user')
          : record.payload,
    );
  }
}
