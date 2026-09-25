import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_remote_datasource.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_model.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_photo_upload.dart';
import 'package:mi_finca_app/features/animals/data/repositories/animal_repository_impl.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const firstPhoto = 'user/animal/550e8400-e29b-41d4-a716-446655440000.jpg';
const secondPhoto = 'user/animal/550e8400-e29b-41d4-a716-446655440001.jpg';

Animal makeAnimal({
  String id = 'animal',
  String? localPath,
  String? remotePath = firstPhoto,
  String name = 'Remote',
  int day = 24,
}) => Animal(
  id: id,
  code: id,
  name: name,
  type: 'Vaca',
  breed: '',
  sex: 'Hembra',
  localPhotoPath: localPath,
  remotePhotoPath: remotePath,
  createdAt: DateTime(2026, 9),
  updatedAt: DateTime(2026, 9, day),
);

void main() {
  late AppDatabase database;
  late AnimalLocalDataSource local;
  late FakeAnimalRemote remote;
  late AnimalRepositoryImpl repository;
  late SupabaseClient client;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    local = AnimalLocalDataSource(database);
    client = SupabaseClient('https://example.test', 'test');
    remote = FakeAnimalRemote(client);
    repository = AnimalRepositoryImpl(local: local, remote: remote);
    await database.writeSetting('session', jsonEncode({'id': 'user'}));
  });
  tearDown(() async {
    await database.close();
    await client.dispose();
  });

  test(
    'fresh device pulls reference without local path or outbox changes',
    () async {
      remote.items = [makeAnimal()];
      final result = await repository.getAll();
      expect(result.single.remotePhotoPath, firstPhoto);
      expect(result.single.localPhotoPath, isNull);
      expect(await database.pendingCount(), 0);
    },
  );

  test(
    'explicit refresh updates a populated device with zero pending',
    () async {
      await local.save(makeAnimal(name: 'Old', day: 23), pending: false);
      remote.items = [makeAnimal(name: 'New', remotePath: secondPhoto)];
      final result = await repository.refreshAnimals();
      expect(result.single.name, 'New');
      expect(result.single.remotePhotoPath, secondPhoto);
      expect(await database.pendingCount(), 0);
    },
  );

  test(
    'normal read remains local-first and does not perform a remote GET',
    () async {
      await local.save(makeAnimal(), pending: false);
      await repository.getAll();
      expect(remote.calls, 0);
    },
  );

  test('same object keeps local file and published checkpoint', () async {
    final animal = makeAnimal(localPath: '/private/photo.jpg');
    await database.putRecord(
      'animals',
      animal.id,
      {
        ...AnimalModel.toJson(animal),
        AnimalPhotoUpload.key: {'status': 'published', 'target': firstPhoto},
      },
      animal.updatedAt,
      pending: false,
    );
    remote.items = [makeAnimal(name: 'Renamed')];
    final result = await repository.refreshAnimals();
    expect(result.single.localPhotoPath, '/private/photo.jpg');
    final saved = (await database.readRecords('animals')).single;
    expect(AnimalPhotoUpload.read(saved)?['status'], 'published');
    expect(await database.pendingCount(), 0);
  });

  test(
    'changed object clears obsolete local reference and upload metadata',
    () async {
      final animal = makeAnimal(localPath: '/private/old.jpg');
      await database.putRecord(
        'animals',
        animal.id,
        {
          ...AnimalModel.toJson(animal),
          AnimalPhotoUpload.key: {'status': 'published', 'target': firstPhoto},
        },
        animal.updatedAt,
        pending: false,
      );
      remote.items = [makeAnimal(remotePath: secondPhoto)];
      final result = await repository.refreshAnimals();
      expect(result.single.localPhotoPath, isNull);
      expect(result.single.remotePhotoPath, secondPhoto);
      expect(
        AnimalPhotoUpload.read((await database.readRecords('animals')).single),
        isNull,
      );
    },
  );

  test('pending photo and animal edits are never overwritten', () async {
    await local.save(makeAnimal(localPath: '/private/new.jpg', name: 'Local'));
    final before = (await database.readRecords('animals')).single;
    remote.items = [makeAnimal(remotePath: secondPhoto)];
    await repository.refreshAnimals();
    final expected = {
      ...before,
      '_sync': {
        ...Map<String, Object?>.from(before['_sync']! as Map),
        'remotePresence': 'confirmed',
      },
    };
    // Positive existence evidence changes; domain/photo/operation bytes do not.
    expect((await database.readRecords('animals')).single, expected);
    expect(await database.pendingCount(), 1);
  });

  test(
    'edit during GET is preserved even if synchronized before response',
    () async {
      await local.save(makeAnimal(name: 'Before'), pending: false);
      remote.items = [makeAnimal(name: 'Stale response')];
      remote.onGet = () async {
        await local.save(makeAnimal(name: 'New local edit'), pending: false);
      };
      final result = await repository.refreshAnimals();
      expect(result.single.name, 'New local edit');
    },
  );

  test('a newly created local animal during GET is not overwritten', () async {
    remote.items = [makeAnimal()];
    remote.onGet = () => local.save(makeAnimal(name: 'Created locally'));
    final result = await repository.refreshAnimals();
    expect(result.single.name, 'Created locally');
    expect(await database.pendingCount(), 1);
  });

  test(
    'server state is accepted for clean records without relying on device clocks',
    () async {
      await local.save(makeAnimal(name: 'Newer', day: 25), pending: false);
      remote.items = [makeAnimal(day: 24)];
      expect((await repository.refreshAnimals()).single.name, 'Remote');
    },
  );

  test(
    'empty remote response is not an instruction to delete animals',
    () async {
      await local.save(makeAnimal(), pending: false);
      remote.items = [];
      expect(await repository.refreshAnimals(), hasLength(1));
    },
  );

  test('failed GET reports failure without changing local data', () async {
    await local.save(makeAnimal(), pending: false);
    remote.onGet = () async => throw const SocketException('offline');
    await expectLater(
      repository.refreshAnimals(),
      throwsA(isA<SocketException>()),
    );
    expect(await local.getAll(), hasLength(1));
    expect(await database.pendingCount(), 0);
  });

  test('logout during GET cannot repopulate the cleared database', () async {
    remote.items = [makeAnimal()];
    remote.onGet = database.clearAll;
    await expectLater(repository.refreshAnimals(), throwsStateError);
    expect(await local.getAll(), isEmpty);
  });

  test('account change during GET rejects the response', () async {
    remote.items = [makeAnimal()];
    remote.onGet = () async => remote.owner = 'other';
    await expectLater(repository.refreshAnimals(), throwsStateError);
    expect(await local.getAll(), isEmpty);
  });

  test(
    'legacy local-only photo is not silently discarded by a refresh',
    () async {
      await local.save(
        makeAnimal(localPath: '/old.jpg', remotePath: null),
        pending: false,
      );
      remote.items = [makeAnimal(remotePath: null)];
      expect(
        (await repository.refreshAnimals()).single.localPhotoPath,
        '/old.jpg',
      );
    },
  );
}

class FakeAnimalRemote extends AnimalRemoteDataSource {
  FakeAnimalRemote(super.client);
  String? owner = 'user';
  int calls = 0;
  List<Animal> items = [];
  Future<void> Function()? onGet;
  @override
  String? get currentUserId => owner;
  @override
  Future<List<Animal>> getAnimals() async {
    calls++;
    await onGet?.call();
    return items;
  }
}
