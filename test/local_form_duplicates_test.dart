import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/core/validation/local_form_duplicates.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:mi_finca_app/features/animals/presentation/screens/animal_screens.dart';
import 'package:mi_finca_app/features/paddocks/presentation/screens/paddock_screens.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'animal_delete_ui_test.dart' show UIAuth, UIPaddocks;
import 'animal_deletion_test.dart' show deletionAnimal;

Map<String, Object?> candidate(
  String id,
  String field,
  String value, {
  String owner = 'owner',
  bool deleted = false,
}) => {
  'id': id,
  field: value,
  '_sync': {'ownerId': owner, 'tombstone': deleted},
};

void main() {
  test(
    'codes remain text, names do not determine animal duplicates, edit excludes UUID',
    () {
      final records = [candidate('a', 'code', '001')..['name'] = 'Colorado'];
      expect(hasLocalFormDuplicate(records, '001', field: 'code'), isTrue);
      expect(hasLocalFormDuplicate(records, '1', field: 'code'), isFalse);
      expect(hasLocalFormDuplicate(records, '002', field: 'code'), isFalse);
      expect(
        hasLocalFormDuplicate(records, '001', field: 'code', excludingId: 'a'),
        isFalse,
      );
      expect(
        hasLocalFormDuplicate(
          [candidate('b', 'code', '001', deleted: true)],
          '001',
          field: 'code',
        ),
        isFalse,
      );
    },
  );
  test(
    'paddock names ignore case and outer spaces and exclude edited UUID',
    () {
      final records = [candidate('p', 'name', ' Pastizal 3 ')];
      expect(
        hasLocalFormDuplicate(
          records,
          'PASTIZAL 3',
          field: 'name',
          ignoreCase: true,
        ),
        isTrue,
      );
      expect(
        hasLocalFormDuplicate(
          records,
          'pastizal 3',
          field: 'name',
          ignoreCase: true,
          excludingId: 'p',
        ),
        isFalse,
      );
      expect(
        hasLocalFormDuplicate(records, '', field: 'name', ignoreCase: true),
        isFalse,
      );
    },
  );
  test(
    'SQLite candidates include pending and synced rows, exclude deleted and other owners',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.writeSetting('session', jsonEncode({'id': 'owner'}));
      for (final row in [
        candidate('pending', 'code', '001'),
        candidate('synced', 'code', '002'),
        candidate('deleted', 'code', '003', deleted: true),
        candidate('other', 'code', '004', owner: 'other'),
      ]) {
        await db.customStatement(
          'INSERT INTO records(collection,id,payload,updated_at,pending) VALUES(?,?,?,?,?)',
          [
            'animals',
            row['id'],
            jsonEncode(row),
            0,
            row['id'] == 'pending' ? 1 : 0,
          ],
        );
      }
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          authViewModelProvider.overrideWith(UIAuth.new),
        ],
      );
      final subscription = container.listen(
        localFormRecordsProvider('animals'),
        (_, _) {},
      );
      final rows = await container.read(
        localFormRecordsProvider('animals').future,
      );
      expect(rows.map((r) => r['id']).toSet(), {'pending', 'synced'});
      subscription.close();
      container.dispose();
      await db.close();
    },
  );
  Future<void> open(
    WidgetTester tester,
    Widget screen,
    String collection,
    List<Map<String, Object?>> rows,
  ) async {
    final container = ProviderContainer(
      overrides: [
        localFormRecordsProvider(
          collection,
        ).overrideWith((ref) => Stream.value(rows)),
        paddockViewModelProvider.overrideWith(UIPaddocks.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(paddockViewModelProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'animal creation blocks Next and shows inline error until code changes',
    (tester) async {
      await open(tester, const AnimalFormScreen(), 'animals', [
        candidate('a', 'code', '001'),
      ]);
      await tester.enterText(find.byType(TextFormField).first, '001');
      await tester.pump();
      expect(find.text(animalDuplicateMessage), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Siguiente'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextFormField).first, '002');
      await tester.pump();
      expect(find.text(animalDuplicateMessage), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Siguiente'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('animal editing excludes its own UUID', (tester) async {
    final animal = deletionAnimal();
    await open(tester, AnimalFormScreen(animal: animal), 'animals', [
      candidate(animal.id, 'code', animal.code),
    ]);
    expect(find.text(animalDuplicateMessage), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Siguiente'))
          .onPressed,
      isNotNull,
    );
  });
  testWidgets('paddock creation blocks save for normalized duplicate', (
    tester,
  ) async {
    await open(tester, const PaddockFormScreen(), 'paddocks', [
      candidate('p', 'name', 'Pastizal 3'),
    ]);
    await tester.enterText(find.byType(TextFormField).first, ' PASTIZAL 3 ');
    await tester.pump();
    expect(find.text(paddockDuplicateMessage), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Agregar potrero'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextFormField).first, 'Pastizal 4');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Agregar potrero'),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'paddock editing excludes own UUID but blocks another paddock name',
    (tester) async {
      final paddock = (await UIPaddocks().build()).last;
      await open(tester, PaddockFormScreen(paddock: paddock), 'paddocks', [
        candidate(paddock.id, 'name', paddock.name),
        candidate('other', 'name', 'Pastizal 3'),
      ]);
      expect(find.text(paddockDuplicateMessage), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar cambios'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.enterText(find.byType(TextFormField).first, 'pastizal 3');
      await tester.pump();
      expect(find.text(paddockDuplicateMessage), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar cambios'),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
