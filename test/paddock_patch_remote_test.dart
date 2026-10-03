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
    collection: paddockPatchCollection,
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
    await remote.pushPaddockPatch(patch({'name': 'Norte'}));
    final r = requests.single;
    expect(r.method, 'PATCH');
    expect(jsonDecode(r.body), {'name': 'Norte'});
    expect(r.url.queryParameters['id'], 'eq.p');
    expect(r.url.queryParameters['user_id'], 'eq.owner');
    expect(r.url.queryParameters['deleted_at'], 'is.null');
    expect(r.url.queryParameters['updated_at'], 'eq.2026-01-01T00:00:00Z');
  });
  test('explicit nullable value remains JSON null', () async {
    await remote.pushPaddockPatch(patch({'pastureType': null}));
    expect(jsonDecode(requests.single.body), {'pasture_type': null});
  });
  test('zero matched rows is conflict not ACK', () async {
    response = [];
    await expectLater(
      remote.pushPaddockPatch(patch({'name': 'Norte'})),
      throwsA(isA<PostgrestException>()),
    );
  });
  test('unexpected ACK identity is rejected', () async {
    response = [
      {'id': 'other', 'user_id': 'owner'},
    ];
    await expectLater(
      remote.pushPaddockPatch(patch({'name': 'Norte'})),
      throwsA(isA<PostgrestException>()),
    );
  });
  test('unknown fields never reach HTTP', () async {
    await expectLater(
      remote.pushPaddockPatch(patch({'paddock_id': 'other'})),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });
  test('frozen CREATE body excludes later projected edit', () async {
    final record = PendingRecord(
      collection: 'paddocks',
      id: 'p',
      updatedAt: DateTime.utc(2026),
      payload: {
        'id': 'p',
        'name': 'Norte',
        '_basePaddockWrite': {'id': 'p', 'name': 'B', 'areaHectares': 2},
        '_sync': SyncMetadata.operation(
          ownerId: 'owner',
          operation: 'upsert',
          revision: 1,
          requestedAt: DateTime.utc(2026),
        ),
      },
    );
    await remote.pushRecord(record);
    expect(jsonDecode(requests.single.body)['name'], 'B');
    expect(requests.single.method, 'POST');
  });
  test(
    'MOVE projection cannot use generic transport even if called directly',
    () async {
      final record = PendingRecord(
        collection: 'paddocks',
        id: 'p',
        updatedAt: DateTime.utc(2026),
        payload: {
          'id': 'p',
          '_moveProjection': {'id': 'move'},
          '_sync': SyncMetadata.operation(
            ownerId: 'owner',
            operation: 'upsert',
            revision: 1,
            requestedAt: DateTime.utc(2026),
          ),
        },
      );
      await expectLater(remote.pushRecord(record), throwsStateError);
      expect(requests, isEmpty);
    },
  );
}
