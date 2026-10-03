import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_patch.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/paddocks/presentation/screens/paddock_screens.dart';

class IntentViewModel extends PaddockViewModel {
  final patches = <PaddockPatch>[];
  @override
  Future<List<Paddock>> build() async => [];
  @override
  Future<void> edit(String id, PaddockPatch patch) async {
    patches.add(patch);
  }

  @override
  Future<void> save(Paddock paddock) async {
    throw StateError('Edit must never save snapshot');
  }
}

void main() {
  for (final nameOnly in [true, false]) {
    testWidgets(
      'form sends only ${nameOnly ? 'name' : 'explicit cleared pasture'} intent despite operational snapshot',
      (tester) async {
        final vm = IntentViewModel();
        final paddock = Paddock(
          id: 'p',
          name: 'B',
          areaHectares: 2,
          pastureType: 'Pasto',
          status: 'En uso',
          grazingStartDate: DateTime.now(),
          plannedGrazingDays: 4,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [paddockViewModelProvider.overrideWith(() => vm)],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => openPaddockForm(context, paddock),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).at(nameOnly ? 0 : 2),
          nameOnly ? 'Norte' : '',
        );
        tester.testTextInput.hide();
        await tester.scrollUntilVisible(
          find.text('Guardar cambios'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Guardar cambios'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Guardar cambios'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          vm.patches.single.localValues,
          nameOnly ? {'name': 'Norte'} : {'pastureType': null},
        );
      },
    );
  }
}
