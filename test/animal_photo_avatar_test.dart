import 'package:mi_finca_app/features/animals/data/services/animal_photo_cache.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_photo_cache_provider.dart';
import 'package:mi_finca_app/core/network/network_status.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_photo_url_source.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_photo_provider.dart';
import 'package:mi_finca_app/features/animals/presentation/widgets/animal_photo_avatar.dart';

const remotePath = 'user/animal/550e8400-e29b-41d4-a716-446655440000.png';
final pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

void main() {
  late PhotoSource source;
  late ImageHttpClient network;
  late Directory directory;
  setUp(() {
    source = PhotoSource();
    network = ImageHttpClient();
    directory = Directory.systemTemp.createTempSync('foto-c-avatar');
    debugNetworkImageHttpClientProvider = () => network;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() async {
    debugNetworkImageHttpClientProvider = null;
    directory.deleteSync(recursive: true);
    await source.changes.close();
  });

  Widget app({
    String? localPath,
    String? path = remotePath,
    AnimalPhotoCache? cache,
    bool online = true,
  }) => ProviderScope(
    overrides: [
      animalPhotoUrlSourceProvider.overrideWithValue(source),
      animalPhotoCacheServiceProvider.overrideWithValue(cache),
      photoNetworkAllowedProvider.overrideWithValue(online),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: AnimalPhotoAvatar(
          animalId: 'animal',
          localPhotoPath: localPath,
          remotePhotoPath: path,
          radius: 28,
          placeholder: const Icon(Icons.pets),
        ),
      ),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    // Flutter image decoding runs outside the fake clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    debugNetworkImageHttpClientProvider = null;
  }

  testWidgets(
    'downloaded photo renders offline after reopening without signing',
    (tester) async {
      var downloads = 0;
      AnimalPhotoCache cache() => AnimalPhotoCache(
        root: () async => directory,
        currentOwner: () async => 'user',
        download: (_, _) async {
          downloads++;
          return pixel;
        },
        validate: (_) async {},
      );
      await tester.runAsync(
        () => cache().get('animal', remotePath, allowNetwork: true),
      );
      await tester.pumpWidget(app(cache: cache(), online: false));
      for (var i = 0; i < 20 && find.byType(Image).evaluate().isEmpty; i++) {
        await settle(tester);
      }
      expect(tester.widget<Image>(find.byType(Image)).image, isA<FileImage>());
      expect(downloads, 1);
      expect(source.calls, 0);
      expect(network.calls, 0);
      await finish(tester);
    },
  );

  testWidgets('offline cache miss shows placeholder without requesting URL', (
    tester,
  ) async {
    await tester.pumpWidget(app(online: false));
    await settle(tester);
    expect(find.byTooltip('Reintentar foto'), findsOneWidget);
    expect(source.calls, 0);
    expect(network.calls, 0);
    await finish(tester);
  });

  testWidgets('existing local image wins and never requests a signed URL', (
    tester,
  ) async {
    final file = File('${directory.path}/photo.png')..writeAsBytesSync(pixel);
    await tester.pumpWidget(app(localPath: file.path));
    await settle(tester);
    expect(source.calls, 0);
    expect(network.calls, 0);
    expect(tester.widget<Image>(find.byType(Image)).image, isA<FileImage>());
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('no local or remote reference uses the existing placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(app(path: null));
    expect(find.byIcon(Icons.pets), findsOneWidget);
    expect(source.calls, 0);
    expect(network.calls, 0);
    await finish(tester);
  });

  testWidgets('missing local file renders the signed remote image', (
    tester,
  ) async {
    await tester.pumpWidget(app(localPath: '/does-not-exist/photo.png'));
    await settle(tester);
    await settle(tester);
    expect(source.calls, 1);
    expect(network.calls, 1);
    expect(tester.widget<Image>(find.byType(Image)).image, isA<NetworkImage>());
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('network 404 shows retry placeholder without looping', (
    tester,
  ) async {
    network.status = 404;
    await tester.pumpWidget(app());
    await settle(tester);
    await settle(tester);
    expect(find.byTooltip('Reintentar foto'), findsOneWidget);
    expect(source.calls, 1);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('401/403 renews only once before showing manual retry', (
    tester,
  ) async {
    network.status = 403;
    await tester.pumpWidget(app());
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
    expect(source.calls, 2);
    expect(network.calls, 2);
    expect(find.byTooltip('Reintentar foto'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('signing error preserves placeholder and supports manual retry', (
    tester,
  ) async {
    source.fail = true;
    await tester.pumpWidget(app());
    await settle(tester);
    await settle(tester);
    expect(find.byTooltip('Reintentar foto'), findsOneWidget);
    expect(source.calls, 1);
    source.fail = false;
    await tester.tap(find.byTooltip('Reintentar foto'));
    await settle(tester);
    await settle(tester);
    expect(source.calls, 2);
    expect(network.calls, 1);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('visible URL renews before expiry without persisting anything', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(source.calls, 1);
    await tester.pump(const Duration(seconds: 571));
    await settle(tester);
    expect(source.calls, 2);
    await finish(tester);
  });
}

class PhotoSource implements AnimalPhotoUrlSource {
  final changes = StreamController<String?>.broadcast();
  int calls = 0;
  bool fail = false;
  @override
  String? get currentUserId => 'user';
  @override
  Stream<String?> get authChanges => changes.stream;
  @override
  Future<String> sign(String animalId, String objectPath, int expiresIn) async {
    calls++;
    if (fail) throw StateError('offline');
    return 'https://example.test/photo.png?token=$calls';
  }
}

class ImageHttpClient implements HttpClient {
  int status = 200;
  int calls = 0;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    calls++;
    return ImageRequest(status);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ImageRequest implements HttpClientRequest {
  ImageRequest(this.status);
  final int status;
  @override
  Future<HttpClientResponse> close() async => ImageResponse(status);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  ImageResponse(this.statusCode);
  @override
  final int statusCode;
  @override
  int get contentLength => pixel.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(pixel).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
