import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/presentation/screens/paddock_screens.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';

class DeletePaddockVm extends PaddockViewModel {
  int deletes = 0;
  @override
  Future<List<Paddock>> build() async => [
    Paddock(
      id: 'p',
      name: 'P',
      areaHectares: 1,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];
  @override
  Future<void> deletePaddock(String id) async {
    deletes++;
    state = const AsyncData([]);
  }
}

class EmptyAnimals extends AnimalViewModel {
  @override
  Future<AnimalState> build() async => const AnimalState();
}

void main() {
  for (final accepted in [false, true]) {
    testWidgets('paddock delete confirmation accepted=$accepted', (
      tester,
    ) async {
      final vm = DeletePaddockVm();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paddockViewModelProvider.overrideWith(() => vm),
            animalViewModelProvider.overrideWith(EmptyAnimals.new),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const PaddockDetailScreen(paddockId: 'p'),
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
      await container.read(animalViewModelProvider.future);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Eliminar potrero'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(accepted ? 'Eliminar' : 'Cancelar'));
      await tester.pumpAndSettle();
      expect(vm.deletes, accepted ? 1 : 0);
      expect(tester.takeException(), isNull);
    });
  }
}
