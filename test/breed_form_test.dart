import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/validation/local_form_duplicates.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/presentation/screens/animal_screens.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'animal_patch_form_test.dart' show AnimalIntentVm, FormPaddocks;

class BreedFormVm extends AnimalIntentVm {
  final saved = <Animal>[];
  @override
  Future<void> save(Animal animal) async => saved.add(animal);
}

void main() {
  for (final editing in [false, true]) {
    for (final scenario in [
      (query: 'Mi cruce ágil', choice: null),
      (query: 'Bra', choice: 'Brahman'),
      (query: 'Desconocida', choice: 'Raza no especificada'),
      (query: 'Sin especificar', choice: 'Raza no especificada'),
    ]) {
      testWidgets(
        'breed form editing=$editing choice=${scenario.choice} query=${scenario.query}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 720);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetViewInsets);
          final vm = BreedFormVm();
          final old = Animal(
            id: 'a',
            code: 'A',
            type: 'Vaca',
            breed: 'Raza anterior libre',
            sex: 'Hembra',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                localFormRecordsProvider(
                  'animals',
                ).overrideWith((ref) => Stream.value(<Map<String, Object?>>[])),
                animalViewModelProvider.overrideWith(() => vm),
                paddockViewModelProvider.overrideWith(FormPaddocks.new),
              ],
              child: MaterialApp(
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              AnimalFormScreen(animal: editing ? old : null),
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
          if (!editing) {
            await tester.enterText(find.byType(TextFormField).first, 'NEW-1');
          }
          final breed = find.widgetWithText(TextFormField, 'Raza *');
          await tester.scrollUntilVisible(
            breed,
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(breed, scenario.query);
          await tester.pumpAndSettle();
          if (scenario.choice != null) {
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            await tester.pumpAndSettle();
            final menuRect = tester.getRect(
              find.byKey(const ValueKey('breed-suggestions')),
            );
            expect(menuRect.bottom, lessThanOrEqualTo(420));
            expect(menuRect.height, greaterThanOrEqualTo(48));
            await tester.tap(find.text(scenario.choice!));
            await tester.pumpAndSettle();
          }
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Siguiente'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('breed-suggestions')), findsNothing);
          await tester.tap(find.text('Siguiente'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Guardar animal'));
          await tester.pumpAndSettle();
          final expected = scenario.choice ?? scenario.query;
          if (editing) {
            expect(vm.patches.single.localValues, {'breed': expected});
            expect(vm.saved, isEmpty);
          } else {
            expect(vm.saved.single.breed, expected);
            expect(vm.patches, isEmpty);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
