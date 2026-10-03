import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_patch.dart';
import 'package:mi_finca_app/features/animals/presentation/screens/animal_screens.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';

class AnimalIntentVm extends AnimalViewModel {
  final patches = <AnimalPatch>[];
  @override
  Future<AnimalState> build() async =>
      const AnimalState(animals: [], movements: []);
  @override
  Future<void> edit(
    String id,
    AnimalPatch patch, {
    String? selectedPhoto,
  }) async {
    patches.add(patch);
  }

  @override
  Future<void> save(Animal animal) async {
    throw StateError('No snapshot edit');
  }
}

class FormPaddocks extends PaddockViewModel {
  @override
  Future<List<Paddock>> build() async => [
    for (final id in ['B', 'C'])
      Paddock(
        id: id,
        name: id,
        areaHectares: 2,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
  ];
}

void main() {
  for (final move in [false, true]) {
    testWidgets(
      'form touched name only; explicit move blocks entire save=$move',
      (tester) async {
        final vm = AnimalIntentVm();
        final animal = Animal(
          id: 'a',
          code: 'A',
          name: 'Luna',
          type: 'Vaca',
          breed: 'X',
          sex: 'Hembra',
          paddockId: 'B',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              animalViewModelProvider.overrideWith(() => vm),
              paddockViewModelProvider.overrideWith(FormPaddocks.new),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AnimalFormScreen(animal: animal),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.text('Open')),
        );
        await container.read(paddockViewModelProvider.future);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(1), 'Luna II');
        tester.testTextInput.hide();
        await tester.tap(find.text('Siguiente'));
        await tester.pumpAndSettle();
        if (move) {
          await tester.tap(find.byType(DropdownButtonFormField<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('C').last);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Siguiente'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Guardar animal'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (move) {
          expect(vm.patches, isEmpty);
          expect(
            find.textContaining('No se guardaron los cambios.'),
            findsOneWidget,
          );
        } else {
          expect(vm.patches.single.localValues, {'name': 'Luna II'});
        }
      },
    );
  }
}
