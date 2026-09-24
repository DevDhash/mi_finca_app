import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_photo_url_source.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_photo_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const photoKey = (
  animalId: 'animal',
  objectPath: 'user/animal/550e8400-e29b-41d4-a716-446655440000.jpg',
);

void main() {
  group('SDK signing', () {
    late SupabaseClient client;
    late List<http.Request> requests;
    setUp(() async {
      requests = [];
      client = SupabaseClient(
        'https://example.test',
        'key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'signedURL':
                  '/object/sign/animal-photos/photo.jpg?token=temporary',
            }),
            200,
          );
        }),
      );
      final token = [
        base64Url.encode(utf8.encode('{}')),
        base64Url.encode(
          utf8.encode(jsonEncode({'sub': 'user', 'exp': 4102444800})),
        ),
        'test',
      ].join('.');
      await client.auth.recoverSession(
        jsonEncode({
          'access_token': token,
          'token_type': 'bearer',
          'refresh_token': 'test',
          'user': {'id': 'user'},
        }),
      );
    });
    tearDown(() => client.dispose());

    test(
      'signs the private object for 600 seconds using the session',
      () async {
        final source = SupabaseAnimalPhotoUrlSource(client);
        final url = await source.sign(
          photoKey.animalId,
          photoKey.objectPath,
          600,
        );
        expect(requests.single.method, 'POST');
        expect(
          requests.single.url.path,
          '/storage/v1/object/sign/animal-photos/${photoKey.objectPath}',
        );
        expect(jsonDecode(requests.single.body), {'expiresIn': 600});
        expect(requests.single.headers['authorization'], startsWith('Bearer '));
        expect(url, contains('?token=temporary'));
        expect(url, isNot(contains('/object/public/')));
      },
    );

    test(
      'rejects foreign owner, foreign animal and local paths before HTTP',
      () async {
        final source = SupabaseAnimalPhotoUrlSource(client);
        for (final path in [
          photoKey.objectPath.replaceFirst('user/', 'other/'),
          photoKey.objectPath.replaceFirst('/animal/', '/other/'),
          '/var/private/a.jpg',
          'https://example.test/a.jpg',
        ]) {
          await expectLater(
            source.sign('animal', path, 600),
            throwsFormatException,
          );
        }
        expect(requests, isEmpty);
      },
    );
  });

  group('memory-only provider', () {
    late FakeUrlSource source;
    late ProviderContainer container;
    setUp(() {
      source = FakeUrlSource();
      container = ProviderContainer(
        overrides: [animalPhotoUrlSourceProvider.overrideWithValue(source)],
      );
    });
    tearDown(() async {
      container.dispose();
      await source.events.close();
    });

    Future<void> initializeSession() async {
      container.listen(animalPhotoSessionProvider, (_, _) {});
      await container.read(animalPhotoSessionProvider.future);
    }

    test('two consumers share a signed URL while watched', () async {
      await initializeSession();
      final a = container.listen(animalPhotoUrlProvider(photoKey), (_, _) {});
      final b = container.listen(animalPhotoUrlProvider(photoKey), (_, _) {});
      expect(
        await container.read(animalPhotoUrlProvider(photoKey).future),
        contains('token=1'),
      );
      expect(source.calls, 1);
      a.close();
      b.close();
    });

    test('manual invalidation requests a fresh URL', () async {
      await initializeSession();
      container.listen(animalPhotoUrlProvider(photoKey), (_, _) {});
      await container.read(animalPhotoUrlProvider(photoKey).future);
      container.invalidate(animalPhotoUrlProvider(photoKey));
      expect(
        await container.read(animalPhotoUrlProvider(photoKey).future),
        contains('token=2'),
      );
    });

    test('signing errors do not start automatic retry loops', () async {
      await initializeSession();
      source.fail = true;
      container.listen(animalPhotoUrlProvider(photoKey), (_, _) {});
      await expectLater(
        container.read(animalPhotoUrlProvider(photoKey).future),
        throwsStateError,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(source.calls, 1);
    });

    test(
      'logout removes previous signed data and prevents another signature',
      () async {
        await initializeSession();
        container.listen(animalPhotoUrlProvider(photoKey), (_, _) {});
        await container.read(animalPhotoUrlProvider(photoKey).future);
        final loggedOut = Completer<void>();
        container.listen(animalPhotoSessionProvider, (_, next) {
          if (next.hasValue && next.value == null && !loggedOut.isCompleted) {
            loggedOut.complete();
          }
        });
        source.owner = null;
        source.events.add(null);
        await loggedOut.future;
        await container.pump();
        await expectLater(
          container.read(animalPhotoUrlProvider(photoKey).future),
          throwsStateError,
        );
        expect(container.read(animalPhotoUrlProvider(photoKey)).asData, isNull);
        expect(source.calls, 1);
      },
    );
  });
}

class FakeUrlSource implements AnimalPhotoUrlSource {
  String? owner = 'user';
  final events = StreamController<String?>.broadcast();
  int calls = 0;
  bool fail = false;
  @override
  String? get currentUserId => owner;
  @override
  Stream<String?> get authChanges => events.stream;
  @override
  Future<String> sign(String animalId, String objectPath, int expiresIn) async {
    calls++;
    if (fail) throw StateError('offline');
    return 'https://example.test/photo?token=$calls';
  }
}
