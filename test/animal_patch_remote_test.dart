import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/sync/data/datasources/supabase_sync_remote_datasource.dart';

void main() {
  late SupabaseClient client;
  late SupabaseSyncRemoteDataSource remote;
  late List<http.Request> requests;
  late List<Map<String, Object?>> response;
  setUp(() async {
    requests = [];
    response = [
      {'id': 'p', 'user_id': 'owner'},
    ];
    client = SupabaseClient(
      'https://example.test',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
          request: r,
        );
      }),
    );
    final token = [
      base64Url.encode(utf8.encode('{}')),
      base64Url.encode(
        utf8.encode(jsonEncode({'sub': 'owner', 'exp': 4102444800})),
      ),
      'test',
    ].join('.');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': token,
        'refresh_token': 'test',
        'token_type': 'bearer',
        'user': {'id': 'owner'},
      }),
    );
    remote = SupabaseSyncRemoteDataSource(client);
  });
  tearDown(() => client.dispose());
  PendingRecord patch(Map<String, Object?> fields) => PendingRecord(
    collection: animalPatchCollection,
    id: 'patch',
    updatedAt: DateTime.utc(2026),
    payload: {
      'entityId': 'p',
      'fields': fields,
      'remoteBaseVersion': '2026-01-01T00:00:00Z',
      '_sync': SyncMetadata.operation(
        ownerId: 'owner',
        operation: 'upsert',
        revision: 1,
        requestedAt: DateTime.utc(2026),
      ),
    },
  );
  test('PATCH body contains only intended name and safe predicates', () async {
    await remote.pushAnimalPatch(patch({'name': 'Norte'}));
    final r = requests.single;
    expect(r.method, 'PATCH');
    expect(jsonDecode(r.body), {'name': 'Norte'});
    expect(r.url.queryParameters['id'], 'eq.p');
    expect(r.url.queryParameters['user_id'], 'eq.owner');
    expect(r.url.queryParameters['deleted_at'], 'is.null');
    expect(r.url.queryParameters['updated_at'], 'eq.2026-01-01T00:00:00Z');
  });
  test('explicit nullable value remains JSON null', () async {
    await remote.pushAnimalPatch(patch({'name': null}));
    expect(jsonDecode(requests.single.body), {'name': null});
  });
  test('zero matched rows is conflict not ACK', () async {
    response = [];
    await expectLater(
      remote.pushAnimalPatch(patch({'name': 'Norte'})),
      throwsA(isA<PostgrestException>()),
    );
  });
  test('unexpected ACK identity is rejected', () async {
    response = [
      {'id': 'other', 'user_id': 'owner'},
    ];
    await expectLater(
      remote.pushAnimalPatch(patch({'name': 'Norte'})),
      throwsA(isA<PostgrestException>()),
    );
  });
  test('unknown fields never reach HTTP', () async {
    await expectLater(
      remote.pushAnimalPatch(patch({'paddock_id': 'other'})),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });

  PendingRecord animal(String kind, {Map<String, Object?> extra = const {}}) =>
      PendingRecord(
        collection: 'animals',
        id: 'p',
        updatedAt: DateTime.utc(2026),
        payload: {
          'id': 'p',
          'name': 'stale',
          'paddockId': 'B',
          'remotePhotoPath': 'owner/p/550e8400-e29b-41d4-a716-446655440000.jpg',
          '_sync': {
            ...SyncMetadata.operation(
              ownerId: 'owner',
              operation: 'upsert',
              revision: 1,
              requestedAt: DateTime.utc(2026),
            ),
            'writeKind': kind,
          },
          ...extra,
        },
      );
  test(
    'photo retry is narrow and cannot restore stale location or name',
    () async {
      for (var i = 0; i < 2; i++) {
        await remote.pushRecord(animal('photo'));
      }
      for (final r in requests) {
        expect(r.method, 'PATCH');
        expect(jsonDecode(r.body), {
          'remote_photo_path':
              'owner/p/550e8400-e29b-41d4-a716-446655440000.jpg',
        });
        expect(r.url.queryParameters['user_id'], 'eq.owner');
        expect(r.url.queryParameters['deleted_at'], 'is.null');
      }
    },
  );
  test(
    'photo patch and location mutation commute in both logical orders',
    () async {
      await remote.pushRecord(animal('photo'));
      final patch = jsonDecode(requests.single.body) as Map;
      for (final firstPhoto in [true, false]) {
        final server = <String, Object?>{'paddock_id': 'B', 'name': 'current'};
        if (firstPhoto) server.addAll(Map<String, Object?>.from(patch));
        server['paddock_id'] = 'C';
        if (!firstPhoto) server.addAll(Map<String, Object?>.from(patch));
        expect(server['paddock_id'], 'C');
        expect(server['name'], 'current');
        expect(server['remote_photo_path'], isNotNull);
      }
    },
  );
  test(
    'CREATE uses frozen initial state and never upserts over conflict',
    () async {
      await remote.pushRecord(
        animal(
          'create',
          extra: {
            '_baseAnimalCreate': {
              'id': 'p',
              'name': 'initial',
              'paddockId': 'B',
            },
          },
        ),
      );
      final request = requests.first;
      expect(request.method, 'POST');
      expect(
        request.headers['prefer'],
        contains('resolution=ignore-duplicates'),
      );
      expect(jsonDecode(request.body)['name'], 'initial');
      expect(jsonDecode(request.body)['paddock_id'], 'B');
    },
  );
  test('ambiguous full record is rejected before HTTP', () async {
    await expectLater(
      remote.pushRecord(animal('legacy_full_write')),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });
  test('MOVE projection cannot become generic animal publication', () async {
    await expectLater(
      remote.pushRecord(
        animal(
          'move_projection',
          extra: {
            '_moveProjection': {'id': 'm1'},
          },
        ),
      ),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });
}
