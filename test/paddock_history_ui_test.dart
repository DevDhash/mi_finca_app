import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:mi_finca_app/features/paddocks/presentation/widgets/movement_history_title.dart';

class HistoryAuth extends AuthViewModel {
  @override
  Future<UserSession?> build() async =>
      const UserSession(id: 'owner', name: 'N', email: 'x@test.com');
  void change(String? id) => state = AsyncData(
    id == null ? null : UserSession(id: id, name: 'N', email: 'x@test.com'),
  );
}

void main() {
  for (final scenario in [
    'active',
    'from deleted',
    'to deleted',
    'null origin',
    'unknown',
    'live tombstone',
    'session change',
    'logout',
  ]) {
    testWidgets('history UI $scenario', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final auth = HistoryAuth();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          authViewModelProvider.overrideWith(() => auth),
        ],
      );
      await db.writeSetting('session', jsonEncode({'id': 'owner'}));
      for (final id in ['A', 'B']) {
        await db.putRecord(
          'paddocks',
          id,
          {'id': id, 'name': id == 'A' ? 'Norte' : 'Sur'},
          DateTime.utc(2026),
          pending: false,
          verifiedRemoteOwner: 'owner',
        );
      }
      Future<void> terminal(String id) => db.mergeRemoteTombstones('owner', [
        RemoteTombstone(
          collection: 'paddocks',
          id: id,
          ownerId: 'owner',
          operationId: 'delete',
          deletedAt: DateTime.utc(2026),
        ),
      ]);
      if (scenario == 'from deleted') await terminal('A');
      if (scenario == 'to deleted') await terminal('B');
      await container.read(authViewModelProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: MovementHistoryTitle(
                movement: Movement(
                  id: 'm',
                  animalId: 'a',
                  fromPaddockId: scenario == 'null origin'
                      ? null
                      : scenario == 'unknown'
                      ? 'unknown-id'
                      : 'A',
                  toPaddockId: 'B',
                  date: DateTime.utc(2026),
                ),
              ),
            ),
          ),
        ),
      );
      // Drain native SQLite futures without assuming a frame completes IO.
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pumpAndSettle();
      }

      await settle();
      if (scenario == 'live tombstone') {
        await tester.runAsync(() => terminal('A'));
        await settle();
      }
      if (scenario == 'session change' || scenario == 'logout') {
        await tester.runAsync(
          () => db.writeSetting('session', jsonEncode({'id': 'other'})),
        );
        auth.change(scenario == 'logout' ? null : 'other');
        await settle();
      }
      final from = switch (scenario) {
        'null origin' => 'Sin potrero de origen',
        'unknown' => 'Potrero unknown-id',
        'from deleted' || 'live tombstone' => 'Norte (eliminado)',
        'session change' || 'logout' => 'Potrero A',
        _ => 'Norte',
      };
      final to = scenario == 'to deleted'
          ? 'Sur (eliminado)'
          : ['session change', 'logout'].contains(scenario)
          ? 'Potrero B'
          : 'Sur';
      expect(find.text('$from → $to'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await db.close();
    });
  }
}
