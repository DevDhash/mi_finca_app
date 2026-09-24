import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_photo_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const target = 'user/animal/550e8400-e29b-41d4-a716-446655440000.jpg';
  late SupabaseClient client;
  late SupabaseAnimalPhotoStorage storage;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;

  setUp(() async {
    requests = [];
    respond = (_) async =>
        http.Response(jsonEncode({'Key': 'animal-photos/$target'}), 200);
    client = SupabaseClient(
      'https://example.test',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) {
        requests.add(request);
        return respond(request);
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
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {'id': 'user'},
      }),
    );
    storage = SupabaseAnimalPhotoStorage(client);
  });
  tearDown(() => client.dispose());

  Future<void> upload() => storage.ensureUploaded(
    ownerId: 'user',
    objectPath: target,
    bytes: Uint8List.fromList([1, 2, 3]),
    digest: 'test-digest',
    contentType: 'image/jpeg',
  );

  test(
    'authenticated SDK uses immutable upload and sends digest metadata',
    () async {
      await upload();
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(
        requests.single.url.path,
        '/storage/v1/object/animal-photos/$target',
      );
      expect(requests.single.headers['x-upsert'], 'false');
      expect(requests.single.headers['authorization'], startsWith('Bearer '));
      expect(requests.single.body, contains('test-digest'));
      expect(requests.single.body, contains('image/jpeg'));
    },
  );

  for (final matches in [true, false]) {
    test('duplicate upload verifies metadata; matching=$matches', () async {
      respond = (request) async {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'statusCode': '400',
              'error': 'Duplicate',
              'message': 'The resource already exists',
            }),
            400,
          );
        }
        return http.Response(
          jsonEncode({
            'id': 'object-id',
            'version': 'version',
            'name': target,
            'bucket_id': 'animal-photos',
            'created_at': '2026-01-01',
            'size': 3,
            'metadata': {'sha256': matches ? 'test-digest' : 'different'},
          }),
          200,
        );
      };
      if (matches) {
        await upload();
      } else {
        await expectLater(upload(), throwsFormatException);
      }
      expect(requests.map((r) => r.method), ['POST', 'GET']);
      expect(
        requests.last.url.path,
        '/storage/v1/object/info/animal-photos/$target',
      );
    });
  }

  test('an arbitrary 400 is not interpreted as a completed upload', () async {
    respond = (_) async => http.Response(
      jsonEncode({
        'statusCode': '400',
        'error': 'InvalidMimeType',
        'message': 'invalid',
      }),
      400,
    );
    await expectLater(upload(), throwsA(isA<StorageException>()));
    expect(requests, hasLength(1));
  });

  test('wrong owner fails before sending any request', () async {
    await expectLater(
      storage.ensureUploaded(
        ownerId: 'other',
        objectPath: target,
        bytes: Uint8List(1),
        digest: 'digest',
        contentType: 'image/jpeg',
      ),
      throwsA(isA<AuthException>()),
    );
    expect(requests, isEmpty);
  });
}
