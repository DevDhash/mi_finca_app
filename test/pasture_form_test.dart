import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/validation/local_form_duplicates.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/presentation/screens/paddock_screens.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'paddock_patch_form_test.dart' show IntentViewModel;

class PastureFormVm extends IntentViewModel {
  final saved = <Paddock>[];
  @override
  Future<void> save(Paddock paddock) async => saved.add(paddock);
}

void main() {
  for (final editing in [false, true]) {
    for (final scenario in [
      (query: 'Setarea', choice: 'Setaria'),
      (query: 'Bra', choice: 'Brachiaria brizantha'),
      (query: 'Mi mezcla ágil', choice: null),
      (query: 'Mar', choice: null),
      (query: '', choice: null),
      (query: null, choice: null),
    ]) {
      testWidgets('pasture form editing=$editing scenario=$scenario', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 720);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        final vm = PastureFormVm();
        final old = Paddock(
          id: 'p',
          name: 'Norte',
          areaHectares: 2,
          pastureType: '  Setarea histórica  ',
          requiredRestDays: 21,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              paddockViewModelProvider.overrideWith(() => vm),
              localFormRecordsProvider(
                'paddocks',
              ).overrideWith((ref) => Stream.value(<Map<String, Object?>>[])),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        openPaddockForm(context, editing ? old : null),
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
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        if (!editing) {
          await tester.enterText(find.byType(TextFormField).first, 'Nuevo');
        }
        final field = find.widgetWithText(TextFormField, 'Tipo de pastura');
        if (editing) {
          expect(
            tester.widget<TextFormField>(field).controller!.text,
            old.pastureType,
          );
        }
        if (scenario.query != null) {
          await tester.ensureVisible(field);
          await tester.enterText(field, scenario.query!);
          await tester.pumpAndSettle();
          if (scenario.choice != null) {
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            await tester.pumpAndSettle();
            final menu = find.byKey(const ValueKey('pasture-suggestions'));
            final rect = tester.getRect(menu);
            expect(rect.bottom, lessThanOrEqualTo(420));
            expect(rect.height, greaterThanOrEqualTo(48));
            await tester.tap(
              find.descendant(of: menu, matching: find.text(scenario.choice!)),
            );
          } else {
            await tester.testTextInput.receiveAction(TextInputAction.done);
            expect(
              tester.widget<TextFormField>(field).controller!.text,
              scenario.query,
            );
          }
        }
        tester.view.resetViewInsets();
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        final button = find.widgetWithText(
          FilledButton,
          editing ? 'Guardar cambios' : 'Agregar potrero',
        );
        await tester.scrollUntilVisible(
          button,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        final text = scenario.choice ?? scenario.query;
        final expected = text == null || text.trim().isEmpty
            ? null
            : text.trim();
        if (editing) {
          expect(vm.saved, isEmpty);
          expect(
            vm.patches.single.localValues,
            scenario.query == null
                ? <String, Object?>{}
                : {'pastureType': expected},
          );
        } else {
          expect(vm.saved.single.pastureType, expected);
          expect(vm.patches, isEmpty);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
