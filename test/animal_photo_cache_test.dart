import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/animals/data/services/animal_photo_cache.dart';

const pathA = 'u/a/550e8400-e29b-41d4-a716-446655440000.jpg';
const pathB = 'u/a/550e8400-e29b-41d4-a716-446655440001.jpg';
void main() {
  late Directory root;
  String? owner;
  var downloads = 0;
  late Future<Uint8List> Function(String, String) fetch;
  AnimalPhotoCache service({int limit = 100}) => AnimalPhotoCache(
    root: () async => root,
    currentOwner: () async => owner,
    download: (u, p) {
      downloads++;
      return fetch(u, p);
    },
    validate: (b) async {
      if (b.isEmpty || b.first != 1) throw const FormatException();
    },
    maxBytes: limit,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('photo-cache-test');
    owner = 'u';
    downloads = 0;
    fetch = (_, _) async => Uint8List.fromList([1, 2, 3]);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('cached photo survives service restart and offline access', () async {
    final file = await service().get('a', pathA, allowNetwork: true);
    final offline = await service().get('a', pathA, allowNetwork: false);
    expect(offline?.path, file?.path);
    expect(downloads, 1);
  });
  test('restart removes interrupted temporary downloads', () async {
    final directory = await Directory('${root.path}/u').create();
    final partial = File('${directory.path}/interrupted.part');
    await partial.writeAsBytes([1]);
    await service().get('a', pathA, allowNetwork: false);
    expect(await partial.exists(), isFalse);
  });
  test('offline cache miss makes no network request', () async {
    expect(await service().get('a', pathA, allowNetwork: false), isNull);
    expect(downloads, 0);
  });
  test(
    'failed download leaves no cached or partial file and can retry',
    () async {
      fetch = (_, _) async => throw const SocketException('offline');
      final cache = service();
      await expectLater(
        cache.get('a', pathA, allowNetwork: true),
        throwsA(isA<SocketException>()),
      );
      expect(await root.list(recursive: true).toList(), isEmpty);
      fetch = (_, _) async => Uint8List.fromList([1]);
      expect(await cache.get('a', pathA, allowNetwork: true), isNotNull);
    },
  );
  test('corrupt cache is discarded and downloaded again', () async {
    final cache = service();
    final file = (await cache.get('a', pathA, allowNetwork: true))!;
    await file.writeAsBytes([0]);
    expect(await cache.get('a', pathA, allowNetwork: true), isNotNull);
    expect(downloads, 2);
  });
  test('concurrent readers download only once', () async {
    final gate = Completer<Uint8List>();
    fetch = (_, _) => gate.future;
    final cache = service();
    final one = cache.get('a', pathA, allowNetwork: true);
    final two = cache.get('a', pathA, allowNetwork: true);
    gate.complete(Uint8List.fromList([1]));
    expect((await one)?.path, (await two)?.path);
    expect(downloads, 1);
  });
  test('replacement has a distinct cached file', () async {
    final cache = service();
    final first = await cache.get('a', pathA, allowNetwork: true);
    final second = await cache.get('a', pathB, allowNetwork: true);
    expect(first?.path, isNot(second?.path));
    expect(downloads, 2);
  });
  test('another owner cannot read the cached photo', () async {
    final cache = service();
    await cache.get('a', pathA, allowNetwork: true);
    owner = 'other';
    await expectLater(
      cache.get('a', pathA, allowNetwork: false),
      throwsFormatException,
    );
  });
  test('late download after session change cannot publish cache', () async {
    final started = Completer<void>();
    final gate = Completer<Uint8List>();
    fetch = (_, _) {
      started.complete();
      return gate.future;
    };
    final cache = service();
    final result = cache.get('a', pathA, allowNetwork: true);
    final assertion = expectLater(result, throwsStateError);
    await started.future;
    owner = null;
    gate.complete(Uint8List.fromList([1]));
    await assertion;
    expect(await root.list(recursive: true).toList(), isEmpty);
  });
  test('logout drains active download before removing owner cache', () async {
    final started = Completer<void>();
    final gate = Completer<Uint8List>();
    fetch = (_, _) {
      started.complete();
      return gate.future;
    };
    final cache = service();
    final assertion = expectLater(
      cache.get('a', pathA, allowNetwork: true),
      throwsStateError,
    );
    await started.future;
    final clear = cache.clearOwner('u');
    gate.complete(Uint8List.fromList([1]));
    await assertion;
    await clear;
    expect(await Directory('${root.path}/u').exists(), isFalse);
  });
  test(
    'cache limit evicts old downloads without touching original photos',
    () async {
      final original = File('${root.path}/original.jpg');
      await original.writeAsBytes([1]);
      final cache = service(limit: 3);
      final first = (await cache.get('a', pathA, allowNetwork: true))!;
      final second = (await cache.get('a', pathB, allowNetwork: true))!;
      expect(await first.exists(), isFalse);
      expect(await second.exists(), isTrue);
      expect(await original.exists(), isTrue);
    },
  );
}
