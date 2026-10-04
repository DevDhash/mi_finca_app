import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_local_datasource.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/paddocks/presentation/screens/paddock_screens.dart';
import 'package:mi_finca_app/features/animals/presentation/screens/animal_screens.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:mi_finca_app/features/farm/presentation/viewmodels/farm_view_model.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';
import 'package:mi_finca_app/features/home/presentation/main_screens.dart';
import 'animal_delete_ui_test.dart' show UIAnimals, UIAuth, UIFarm, UISync;

class LocalOperationalPaddocks extends PaddockViewModel {
  @override
  Future<List<Paddock>> build() =>
      ref.read(paddockLocalDataSourceProvider).getAll();
}

void main() {
  for (final entry in <String, Widget>{
    'list': const PaddockListScreen(),
    'individual MOVE': const MoveAnimalScreen(animalId: 'a'),
    'batch MOVE': const MoveAnimalBatchScreen(),
    'rotation order': const PaddockRotationOrderScreen(),
    'dashboard': const DashboardScreen(),
  }.entries) {
    testWidgets('historical deleted paddock excluded from ${entry.key}', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.writeSetting('session', jsonEncode({'id': 'owner'}));
      final local = PaddockLocalDataSource(db);
      for (final id in ['p1', 'p2', 'deleted']) {
        await local.save(
          Paddock(
            id: id,
            name: id == 'deleted' ? 'HISTORICAL ONLY' : id,
            areaHectares: 1,
            status: id == 'p1' ? 'En uso' : 'Disponible',
            rotationOrder: id == 'p1'
                ? 1
                : id == 'deleted'
                ? 2
                : 3,
            requiredRestDays: 1,
            lastGrazingEndDate: DateTime(2020),
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
          pending: false,
          verifiedRemoteOwner: 'owner',
        );
      }
      await db.markDeleted('paddocks', 'deleted', 'owner');
      expect(
        (await local.resolveHistory({'deleted'}))['deleted']!.label,
        'HISTORICAL ONLY (eliminado)',
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          paddockViewModelProvider.overrideWith(LocalOperationalPaddocks.new),
          animalViewModelProvider.overrideWith(UIAnimals.new),
          authViewModelProvider.overrideWith(UIAuth.new),
          farmViewModelProvider.overrideWith(UIFarm.new),
          syncViewModelProvider.overrideWith(UISync.new),
          monthlyExpenseTotalProvider.overrideWithValue(0),
        ],
      );
      await container.read(paddockViewModelProvider.future);
      await container.read(animalViewModelProvider.future);
      await container.read(authViewModelProvider.future);
      await container.read(farmViewModelProvider.future);
      await container.read(syncViewModelProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: entry.value),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('HISTORICAL ONLY'), findsNothing);
      expect(
        container.read(paddockViewModelProvider).requireValue.map((p) => p.id),
        isNot(contains('deleted')),
      );
      if (entry.key.contains('MOVE')) {
        final dropdowns = tester.widgetList<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        );
        expect(dropdowns, isNotEmpty);
        // Open each rendered picker; no historical label may become selectable.
        for (final picker
            in find
                .byType(DropdownButtonFormField<String>)
                .evaluate()
                .toList()) {
          await tester.ensureVisible(find.byWidget(picker.widget));
          await tester.tap(find.byWidget(picker.widget));
          await tester.pumpAndSettle();
          expect(find.textContaining('HISTORICAL ONLY'), findsNothing);
          await tester.tapAt(const Offset(1, 1));
          await tester.pumpAndSettle();
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await db.close();
    });
  }
}
