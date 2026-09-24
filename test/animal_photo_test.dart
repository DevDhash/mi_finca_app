import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_model.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_remote_payload.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/presentation/widgets/local_animal_photo_avatar.dart';

const remotePath = 'user/animal/550e8400-e29b-41d4-a716-446655440000.jpg';
Animal animal() => Animal(
  id: 'animal',
  code: 'V-001',
  type: 'Vaca',
  breed: 'Holstein',
  sex: 'Hembra',
  localPhotoPath: '/data/user/0/animal_photos/photo.jpg',
  remotePhotoPath: remotePath,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  test('local JSON round trips both paths without emitting legacy key', () {
    final value = animal();
    final json = AnimalModel.toJson(value);
    expect(json['localPhotoPath'], value.localPhotoPath);
    expect(json['remotePhotoPath'], remotePath);
    expect(json.containsKey('photoPath'), isFalse);
    final restored = AnimalModel.fromJson(json);
    expect(restored.localPhotoPath, value.localPhotoPath);
    expect(restored.remotePhotoPath, remotePath);
  });

  for (final path in ['/data/user/0/a.jpg', '/Users/me/a.jpg', '/var/a.jpg']) {
    test('legacy $path remains local only', () {
      final json = AnimalModel.toJson(animal())
        ..remove('localPhotoPath')
        ..remove('remotePhotoPath')
        ..['photoPath'] = path;
      final restored = AnimalModel.fromJson(json);
      expect(restored.localPhotoPath, path);
      expect(restored.remotePhotoPath, isNull);
      final remote = AnimalRemotePayload.fromLocal(json, 'user');
      expect(remote['remote_photo_path'], isNull);
      expect(remote.values, isNot(contains(path)));
    });
  }

  test('new local key wins over legacy including explicit null', () {
    final json = AnimalModel.toJson(animal())..['photoPath'] = '/old.jpg';
    expect(AnimalModel.fromJson(json).localPhotoPath, animal().localPhotoPath);
    json['localPhotoPath'] = null;
    expect(AnimalModel.fromJson(json).localPhotoPath, isNull);
  });

  test('copyWith preserves omitted paths and clears explicit null', () {
    final original = animal();
    expect(
      original.copyWith(code: 'V-002').localPhotoPath,
      original.localPhotoPath,
    );
    expect(original.copyWith().remotePhotoPath, remotePath);
    final cleared = original.copyWith(
      localPhotoPath: null,
      remotePhotoPath: null,
    );
    expect(cleared.localPhotoPath, isNull);
    expect(cleared.remotePhotoPath, isNull);
  });

  test('shared remote whitelist excludes device and legacy fields', () {
    final payload = AnimalModel.toJson(animal())..['photoPath'] = '/old.jpg';
    final remote = AnimalRemotePayload.fromLocal(payload, 'user');
    expect(remote['remote_photo_path'], remotePath);
    for (final key in [
      'localPhotoPath',
      'photoPath',
      'photo_path',
      'remotePhotoPath',
    ]) {
      expect(remote.containsKey(key), isFalse);
    }
    expect(remote.values, isNot(contains(animal().localPhotoPath)));
    expect(remote.values, isNot(contains('/old.jpg')));
  });

  test('remote mapper rejects absolute paths, URLs and wrong owners', () {
    for (final value in [
      '/data/user/0/a.jpg',
      '/Users/me/a.jpg',
      '/var/a.jpg',
      r'C:\photos\a.jpg',
      'https://example.com/a.jpg?token=secret',
      'animal-photos/$remotePath',
      'other/animal/550e8400-e29b-41d4-a716-446655440000.jpg',
      'user/other/550e8400-e29b-41d4-a716-446655440000.jpg',
    ]) {
      expect(
        () => AnimalRemotePayload.fromLocal({
          ...AnimalModel.toJson(animal()),
          'remotePhotoPath': value,
        }, 'user'),
        throwsFormatException,
      );
    }
  });

  test(
    'SQLite reads old payload and writes new fields without schema changes',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final local = AnimalLocalDataSource(database);
      final legacy = AnimalModel.toJson(animal())
        ..remove('localPhotoPath')
        ..remove('remotePhotoPath')
        ..['photoPath'] = '/var/legacy.jpg';
      await database.putRecord('animals', 'animal', legacy, DateTime(2026));
      final restored = (await local.getAll()).single;
      expect(restored.localPhotoPath, '/var/legacy.jpg');
      expect(restored.remotePhotoPath, isNull);
      await local.save(restored.copyWith(remotePhotoPath: remotePath));
      final stored = (await database.readRecords('animals')).single;
      expect(stored['localPhotoPath'], '/var/legacy.jpg');
      expect(stored['remotePhotoPath'], remotePath);
      expect(stored.containsKey('photoPath'), isFalse);
      expect(await database.pendingCount(), 1);
    },
  );

  for (final path in [null, '/does-not-exist/animal-photo.jpg']) {
    testWidgets('missing local photo $path renders placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LocalAnimalPhotoAvatar(
            localPhotoPath: path,
            radius: 28,
            placeholder: const Icon(Icons.pets),
          ),
        ),
      );
      expect(find.byIcon(Icons.pets), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unreadable image falls back without an uncaught error', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('animal-photo-test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/broken.jpg')
      ..writeAsStringSync('invalid image');
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: LocalAnimalPhotoAvatar(
            localPhotoPath: file.path,
            radius: 28,
            placeholder: const Icon(Icons.pets),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      final stream = image.image.resolve(ImageConfiguration.empty);
      final finished = Completer<void>();
      final listener = ImageStreamListener(
        (_, synchronousCall) => finished.complete(),
        onError: (Object error, StackTrace? stack) => finished.complete(),
      );
      stream.addListener(listener);
      try {
        await finished.future.timeout(const Duration(seconds: 5));
      } finally {
        stream.removeListener(listener);
      }
    });
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pets), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
