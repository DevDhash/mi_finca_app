import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/validation/local_form_duplicates.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_local_datasource.dart';
import 'package:mi_finca_app/features/paddocks/data/models/paddock_model.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_patch.dart';
import 'package:mi_finca_app/features/paddocks/presentation/screens/paddock_screens.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'paddock_patch_form_test.dart' show IntentViewModel;
import 'paddock_delete_ui_test.dart' show EmptyAnimals;

Paddock paddockWithArea(double? area) => Paddock(
  id: 'p',
  name: 'Norte',
  areaHectares: area,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class AreaPaddocks extends PaddockViewModel {
  @override
  Future<List<Paddock>> build() async => [
    paddockWithArea(null),
    paddockWithArea(1).copyWith(name: 'Sur'),
  ];
}

void main() {
  for (final area in <double?>[null, 1, 2.75, 0, -1]) {
    test('JSON preserves area $area', () {
      final encoded =
          jsonDecode(jsonEncode(PaddockModel.toJson(paddockWithArea(area))))
              as Map<String, dynamic>;
      expect(encoded.containsKey('areaHectares'), isTrue);
      expect(PaddockModel.fromJson(encoded).areaHectares, area);
    });
  }
  test('missing area is unknown but invalid data is rejected', () {
    final json = PaddockModel.toJson(paddockWithArea(1))
      ..remove('areaHectares');
    expect(PaddockModel.fromJson(json).areaHectares, isNull);
    json['areaHectares'] = 'invalid';
    expect(() => PaddockModel.fromJson(json), throwsA(isA<TypeError>()));
  });
  test('copyWith distinguishes omitted, numeric and explicit null area', () {
    final original = paddockWithArea(1);
    expect(original.copyWith(name: 'Sur').areaHectares, 1);
    expect(original.copyWith(areaHectares: null).areaHectares, isNull);
    expect(paddockWithArea(null).copyWith(areaHectares: 2.5).areaHectares, 2.5);
  });
  test('SQLite preserves null and subsequent field-only edits', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.writeSetting('session', jsonEncode({'id': 'owner'}));
    final local = PaddockLocalDataSource(db);
    await local.save(paddockWithArea(null));
    expect((await local.getAll()).single.areaHectares, isNull);
    expect(
      (await db.readRecord(
        'paddocks',
        'p',
      ))!.payload.containsKey('areaHectares'),
      isTrue,
    );
    await local.edit('p', PaddockPatch({PaddockField.name: 'Sur'}));
    expect((await local.getAll()).single.areaHectares, isNull);
    await local.edit('p', PaddockPatch({PaddockField.area: 3.5}));
    expect((await local.getAll()).single.areaHectares, 3.5);
    expect((await db.paddockPatches('owner')).map((p) => p.payload['fields']), [
      {'name': 'Sur'},
      {'areaHectares': 3.5},
    ]);
  });
  for (final detail in [false, true]) {
    testWidgets('unknown area displayed detail=$detail', (tester) async {
      final container = ProviderContainer(
        overrides: [
          paddockViewModelProvider.overrideWith(AreaPaddocks.new),
          animalViewModelProvider.overrideWith(EmptyAnimals.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(paddockViewModelProvider.future);
      await container.read(animalViewModelProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: detail
                ? const PaddockDetailScreen(paddockId: 'p')
                : const PaddockListScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Sin registrar'), findsOneWidget);
      if (!detail) {
        await tester.scrollUntilVisible(
          find.text('1.0 ha'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('1.0 ha'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final clear in [false, true]) {
    testWidgets('area-only edit clear=$clear', (tester) async {
      final vm = IntentViewModel();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paddockViewModelProvider.overrideWith(() => vm),
            localFormRecordsProvider(
              'paddocks',
            ).overrideWith((ref) => Stream.value([])),
          ],
          child: MaterialApp(
            home: PaddockFormScreen(paddock: paddockWithArea(clear ? 1 : null)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        clear ? '1.0' : '',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        clear ? '' : '2,5',
      );
      tester.testTextInput.hide();
      await tester.scrollUntilVisible(
        find.text('Guardar cambios'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(vm.patches.single.localValues, {
        'areaHectares': clear ? null : 2.5,
      });
    });
  }
}
