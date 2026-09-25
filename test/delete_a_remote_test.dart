import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/sync/data/datasources/supabase_sync_remote_datasource.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late SupabaseSyncRemoteDataSource remote;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  Map<String, Object?> tombstone({int sequence = 1, String owner = 'owner'}) =>
      {
        'sequence': sequence,
        'collection': 'expenses',
        'entity_id': 'expense-id',
        'user_id': owner,
        'operation_id': 'accepted-operation',
        'deleted_at': '2026-09-25T00:00:00Z',
      };
  PendingRecord record({String owner = 'owner', String operation = 'delete'}) =>
      PendingRecord(
        collection: 'expenses',
        id: 'expense-id',
        updatedAt: DateTime.utc(2000),
        payload: {
          'id': 'expense-id',
          'amount': 25,
          '_sync': SyncMetadata.operation(
            ownerId: owner,
            operation: operation,
            revision: 4,
            requestedAt: DateTime.utc(2000),
          ),
        },
      );
  setUp(() async {
    requests = [];
    respond = (_) async => http.Response(
      jsonEncode(tombstone()),
      200,
      headers: {'content-type': 'application/json'},
    );
    client = SupabaseClient(
      'https://example.test',
      'key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = await respond(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
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
  test(
    'DELETE uses authenticated RPC with persisted intent, never HTTP DELETE or phone timestamp',
    () async {
      final pending = record();
      final response = await remote.softDelete(pending);
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/rest/v1/rpc/sync_soft_delete');
      expect(requests.single.headers['authorization'], startsWith('Bearer '));
      expect(jsonDecode(requests.single.body), {
        'p_collection': 'expenses',
        'p_entity_id': pending.id,
        'p_owner_id': 'owner',
        'p_operation_id': pending.operationId,
      });
      expect(response.deletedAt, DateTime.utc(2026, 9, 25));
      expect(response.operationId, 'accepted-operation');
    },
  );
  test(
    'retry sends identical operation and accepts first server deletion time',
    () async {
      final pending = record();
      final one = await remote.softDelete(pending);
      final two = await remote.softDelete(pending);
      expect(requests[0].body, requests[1].body);
      expect(one.deletedAt, two.deletedAt);
    },
  );
  test('wrong account or UPSERT cannot invoke deletion endpoint', () async {
    await expectLater(
      remote.softDelete(record(owner: 'other')),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      remote.softDelete(record(operation: 'upsert')),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });
  test('foreign response cannot acknowledge deletion', () async {
    respond = (_) async =>
        http.Response(jsonEncode(tombstone(owner: 'other')), 200);
    await expectLater(remote.softDelete(record()), throwsStateError);
  });
  test(
    'short server pages are followed until an explicit empty page',
    () async {
      respond = (request) async {
        final after = request.url.queryParameters['sequence'];
        final rows = after == 'gt.0'
            ? [tombstone(sequence: 3)]
            : after == 'gt.3'
            ? [tombstone(sequence: 8)]
            : [];
        return http.Response(jsonEncode(rows), 200);
      };
      expect(await remote.fetchTombstones('owner'), hasLength(2));
      expect(requests, hasLength(3));
      for (final request in requests) {
        expect(request.method, 'GET');
        expect(request.url.queryParameters['user_id'], 'eq.owner');
        expect(request.url.path, '/rest/v1/sync_deletions');
      }
    },
  );
  test('empty pull returns no tombstones', () async {
    respond = (_) async => http.Response('[]', 200);
    expect(await remote.fetchTombstones('owner'), isEmpty);
  });
  test(
    'UPSERT whitelist does not send protocol metadata or deleted_at',
    () async {
      respond = (_) async => http.Response('', 201);
      await remote.pushRecord(record(operation: 'upsert'));
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['user_id'], 'owner');
      expect(body['amount'], 25);
      expect(body.containsKey('_sync'), false);
      expect(body.containsKey('deleted_at'), false);
    },
  );
  test(
    'unverified legacy UPSERT is rejected before any network request',
    () async {
      await expectLater(
        remote.pushRecord(
          PendingRecord(
            collection: 'expenses',
            id: 'e',
            payload: {'id': 'e'},
            updatedAt: DateTime.now(),
          ),
        ),
        throwsStateError,
      );
      expect(requests, isEmpty);
    },
  );
}
