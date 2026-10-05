import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_remote_datasource.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_remote_datasource.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_remote_datasource.dart';

void main() {
  for (final table in ['animals', 'paddocks', 'animal_movements', 'expenses']) {
    test(
      '$table fetch paginates beyond a capped short page with owner and active filters',
      () async {
        final requests = <http.Request>[];
        final client = SupabaseClient(
          'https://example.test',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            requests.add(request);
            final after = request.url.queryParameters['id'];
            final id = after == null
                ? 'a'
                : after == 'gt.a'
                ? 'b'
                : null;
            final row = <String, Object?>{
              'id': id,
              'code': id,
              'type': 'Vaca',
              'name': id,
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
              'area': 1,
              'animal_id': 'animal',
              'to_paddock_id': 'p',
              'moved_at': '2026-01-01T00:00:00Z',
              'category': 'Alimento',
              'amount': 1,
              'date': '2026-01-01T00:00:00Z',
            };
            return http.Response(
              jsonEncode(id == null ? [] : [row]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
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
        final List<dynamic> rows;
        switch (table) {
          case 'animals':
            rows = await AnimalRemoteDataSource(client).getAnimals();
          case 'paddocks':
            rows = await PaddockRemoteDataSource(client).getAll();
          case 'animal_movements':
            rows = await AnimalRemoteDataSource(client).getMovements();
          default:
            rows = await ExpenseRemoteDataSource(client).getAll();
        }
        expect(rows.length, 2);
        expect(requests.length, 3);
        expect(requests.map((r) => r.url.queryParameters['id']), [
          null,
          'gt.a',
          'gt.b',
        ]);
        for (final request in requests) {
          expect(request.url.path, '/rest/v1/$table');
          expect(request.url.queryParameters['user_id'], 'eq.owner');
          expect(request.url.queryParameters['deleted_at'], 'is.null');
          expect(request.url.queryParameters['order'], startsWith('id.asc'));
          expect(request.url.queryParameters['limit'], '500');
        }
      },
    );
  }
}
