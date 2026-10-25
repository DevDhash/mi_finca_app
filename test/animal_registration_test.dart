import 'package:mi_finca_app/features/animals/domain/constants/cattle_categories.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_patch.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_model.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_remote_payload.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/validation/local_form_duplicates.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/validators/animal_registration.dart';
import 'package:mi_finca_app/features/animals/presentation/screens/animal_screens.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/animals/presentation/widgets/breed_autocomplete_field.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';

class RegistrationVm extends AnimalViewModel {
  final saved = <Animal>[];
  final patches = <AnimalPatch>[];
  @override
  Future<void> edit(
    String id,
    AnimalPatch patch, {
    String? selectedPhoto,
  }) async {
    patches.add(patch);
  }

  @override
  Future<AnimalState> build() async => const AnimalState();
  @override
  Future<void> save(Animal animal) async => saved.add(animal);
}

class EmptyPaddocks extends PaddockViewModel {
  @override
  Future<List<Paddock>> build() async => [];
}

void main() {
  testWidgets('external labels and examples leave the draft empty', (
    tester,
  ) async {
    await mount(tester, RegistrationVm());
    for (final label in [
      'Código / arete :',
      'Nombre del animal :',
      'Raza :',
    ]) {
      expect(find.text(label), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(label)).style,
        tester.widget<Text>(find.text('Tipo')).style,
      );
    }
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.map((field) => field.decoration?.hintText), [
      'Ej. 001',
      'Ej. Toribio',
      'Ej. Holstein',
    ]);
    for (final field in fields) {
      expect(field.controller!.text, isEmpty);
      expect(field.decoration?.labelText, isNull);
    }
    await next(tester);
    expect(find.text('Ingresa un código o arete'), findsOneWidget);
    expect(find.text('Selecciona o ingresa una raza'), findsOneWidget);
  });

  for (final animalCode in ['001', 'A-001']) {
    testWidgets('external fields retain $animalCode across steps and save', (
      tester,
    ) async {
      final vm = RegistrationVm();
      await mount(tester, vm);
      await fillFirst(tester);
      await tester.enterText(find.byType(TextFormField).first, animalCode);
      await next(tester);
      await tester.tap(find.text('Atrás'));
      await tester.pumpAndSettle();
      final fields = tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      );
      expect(fields.map((field) => field.controller!.text), [
        animalCode,
        '',
        'Criollo',
      ]);
      await next(tester);
      await next(tester);
      await tester.tap(find.text('Guardar animal'));
      await tester.pumpAndSettle();
      expect(vm.saved.single.code, animalCode);
      expect(vm.saved.single.name, isNull);
      expect(vm.saved.single.breed, 'Criollo');
    });
  }

  testWidgets('type help preserves draft, manual sex and keyboard input', (
    tester,
  ) async {
    final vm = RegistrationVm();
    await mount(tester, vm);
    await fillFirst(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Otro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hembra'));
    await tester.enterText(find.byType(TextFormField).first, 'AYUDA-01');
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byTooltip('Información sobre el tipo de animal'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('¿Cómo identificar el tipo de animal?'), findsOneWidget);
    expect(find.text('Edad referencial: de 0 a 1.5 años.'), findsOneWidget);
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.text('AYUDA-01'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Otro'))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected,
      {'Hembra'},
    );
    expect(vm.saved, isEmpty);
    await next(tester);
    await next(tester);
    await tester.tap(find.text('Guardar animal'));
    await tester.pumpAndSettle();
    expect(vm.saved.single.code, 'AYUDA-01');
    expect(vm.saved.single.breed, 'Criollo');
    expect(vm.saved.single.type, 'Otro');
    expect(vm.saved.single.sex, 'Hembra');
  });

  testWidgets('type help does not add fields to an edit patch', (tester) async {
    final vm = RegistrationVm();
    await mount(
      tester,
      vm,
      animal: Animal(
        id: 'help-edit',
        code: 'A',
        type: 'Vaca',
        breed: 'Criollo',
        sex: 'Hembra',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    await tester.tap(find.byTooltip('Información sobre el tipo de animal'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), 'Luna');
    await next(tester);
    await next(tester);
    await tester.tap(find.text('Guardar animal'));
    await tester.pumpAndSettle();
    expect(vm.patches.single.localValues, {'name': 'Luna'});
    expect(tester.takeException(), isNull);
  });

  for (final category in CattleCategories.sexes.entries) {
    testWidgets('${category.key} registration persists correct sex', (
      tester,
    ) async {
      final vm = RegistrationVm();
      await mount(tester, vm);
      await fillFirst(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, category.key));
      await tester.pumpAndSettle();
      expect(
        find.byType(SegmentedButton<String>),
        category.value == null ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Sexo del animal :'),
        category.value == null ? findsOneWidget : findsNothing,
      );
      if (category.value == null) {
        expect(
          tester
              .widget<SegmentedButton<String>>(
                find.byType(SegmentedButton<String>),
              )
              .selected,
          isEmpty,
        );
        await next(tester);
        expect(find.text('Selecciona el sexo del animal'), findsOneWidget);
        await tester.tap(find.text('Hembra'));
      }
      await next(tester);
      await next(tester);
      await tester.tap(find.text('Guardar animal'));
      await tester.pumpAndSettle();
      final animal = vm.saved.single;
      expect(animal.type, category.key);
      expect(animal.sex, category.value ?? 'Hembra');
      final json = AnimalModel.toJson(animal);
      expect(AnimalModel.fromJson(json).sex, animal.sex);
      final remote = AnimalRemotePayload.fromLocal(json, 'owner');
      expect(remote['type'], animal.type);
      expect(remote['sex'], animal.sex);
    });
  }

  testWidgets('category transitions clear manual selection and hide selector', (
    tester,
  ) async {
    await mount(tester, RegistrationVm());
    for (final category in [
      'Vaca',
      'Toro',
      'Ternero',
      'Otro',
      'Torete',
      'Otro',
      'Vaca',
    ]) {
      await tester.tap(find.widgetWithText(ChoiceChip, category));
      await tester.pumpAndSettle();
      if (category == 'Otro') {
        expect(find.text('Sexo del animal :'), findsOneWidget);
        final selector = tester.widget<SegmentedButton<String>>(
          find.byType(SegmentedButton<String>),
        );
        expect(selector.selected, isEmpty);
        await tester.tap(find.text('Hembra'));
      } else {
        expect(find.text('Sexo del animal :'), findsNothing);
        expect(find.byType(SegmentedButton<String>), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('seven categories wrap compactly on a small screen', (
    tester,
  ) async {
    await mount(tester, RegistrationVm());
    tester.view.physicalSize = const Size(320, 900);
    await tester.pumpAndSettle();
    final chips = find.byType(ChoiceChip);
    expect(chips, findsNWidgets(7));
    final first = tester.getRect(find.widgetWithText(ChoiceChip, 'Toro'));
    final second = tester.getRect(find.widgetWithText(ChoiceChip, 'Vaca'));
    expect(first.top, second.top);
    expect(second.left - first.right, closeTo(8, 0.01));
    for (final category in CattleCategories.sexes.keys) {
      final rect = tester.getRect(find.widgetWithText(ChoiceChip, category));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Otro'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Otro'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(SegmentedButton<String>),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    final label = find.text('Sexo del animal :');
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    final labelRect = tester.getRect(label);
    final selectorRect = tester.getRect(find.byType(SegmentedButton<String>));
    expect(labelRect.left, greaterThanOrEqualTo(0));
    expect(labelRect.right, lessThanOrEqualTo(320));
    expect(selectorRect.top - labelRect.bottom, closeTo(8, 0.01));
    expect(selectorRect.right, lessThanOrEqualTo(320));
    expect(
      tester.widget<Text>(label).style,
      tester.widget<Text>(find.text('Tipo')).style,
    );
    expect(tester.takeException(), isNull);
  });

  for (final savedSex in ['Hembra', 'Macho']) {
    testWidgets('editing Otro retains saved $savedSex without changing sex', (
      tester,
    ) async {
      final vm = RegistrationVm();
      await mount(
        tester,
        vm,
        animal: Animal(
          id: 'other',
          code: 'A',
          type: 'Otro',
          breed: 'Criollo',
          sex: savedSex,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      expect(find.text('Sexo del animal :'), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<String>>(
              find.byType(SegmentedButton<String>),
            )
            .selected,
        {savedSex},
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'Luna');
      await next(tester);
      await next(tester);
      await tester.tap(find.text('Guardar animal'));
      await tester.pumpAndSettle();
      expect(vm.patches.single.localValues, {'name': 'Luna'});
      expect(tester.takeException(), isNull);
    });
  }

  for (final original in ['Vaca', 'Otro']) {
    testWidgets(
      'edit $original initializes and persists category and sex together',
      (tester) async {
        final vm = RegistrationVm();
        final animal = Animal(
          id: 'a',
          code: 'A',
          type: original,
          breed: 'Criollo',
          sex: 'Hembra',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        await mount(tester, vm, animal: animal);
        if (original == 'Otro') {
          expect(
            tester
                .widget<SegmentedButton<String>>(
                  find.byType(SegmentedButton<String>),
                )
                .selected,
            {'Hembra'},
          );
        } else {
          expect(find.byType(SegmentedButton<String>), findsNothing);
        }
        await tester.tap(find.widgetWithText(ChoiceChip, 'Toro'));
        await tester.pumpAndSettle();
        await next(tester);
        await next(tester);
        await tester.tap(find.text('Guardar animal'));
        await tester.pumpAndSettle();
        expect(vm.patches.single.localValues, {'type': 'Toro', 'sex': 'Macho'});
        expect(vm.patches.single.remoteValues, {
          'type': 'Toro',
          'sex': 'Macho',
        });
      },
    );
  }

  for (final value in ['', '   ']) {
    test('code and breed reject <$value>', () {
      expect(AnimalRegistration.codeError(value), isNotNull);
      expect(AnimalRegistration.breedError(value), isNotNull);
    });
  }
  for (final value in ['', '0', '123.5', '123,5']) {
    test('optional or valid weight <$value>', () {
      expect(AnimalRegistration.weightError(value), isNull);
    });
  }
  for (final value in ['-1', 'abc', 'NaN', 'Infinity', '1e999']) {
    test('invalid weight <$value>', () {
      expect(AnimalRegistration.weightError(value), isNotNull);
    });
  }
  testWidgets('empty stage shows every mandatory error and retains values', (
    tester,
  ) async {
    final vm = RegistrationVm();
    await mount(tester, vm);
    expect(find.widgetWithText(ActionChip, 'No especificada'), findsNothing);
    await next(tester);
    expect(find.text('Ingresa un código o arete'), findsOneWidget);
    expect(find.text('Selecciona el tipo de animal'), findsOneWidget);
    expect(find.text('Selecciona o ingresa una raza'), findsOneWidget);
    expect(vm.saved, isEmpty);
  });
  for (final missing in ['code', 'spaces', 'type', 'breed', 'sex']) {
    testWidgets('first stage blocks missing $missing', (tester) async {
      final vm = RegistrationVm();
      await mount(tester, vm);
      if (missing != 'code') {
        await tester.enterText(
          find.byType(TextFormField).first,
          missing == 'spaces' ? '   ' : 'A-1',
        );
      }
      if (missing != 'type') {
        await tester.tap(
          find.widgetWithText(ChoiceChip, missing == 'sex' ? 'Otro' : 'Vaca'),
        );
      }
      if (missing != 'breed') {
        final breedField = tester.widget<BreedAutocompleteField>(
          find.byType(BreedAutocompleteField),
        );

        await tester.enterText(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextFormField &&
                widget.controller == breedField.controller,
          ),
          'Criollo',
        );
      }
      await next(tester);
      expect(find.text('Peso estimado'), findsNothing);
      final message = switch (missing) {
        'code' || 'spaces' => 'Ingresa un código o arete',
        'type' => 'Selecciona el tipo de animal',
        'breed' => 'Selecciona o ingresa una raza',
        _ => 'Selecciona el sexo del animal',
      };
      expect(find.text(message), findsOneWidget);
      expect(vm.saved, isEmpty);
    });
  }
  testWidgets(
    'valid explicit selections and manual breed save with empty optionals',
    (tester) async {
      final vm = RegistrationVm();
      await mount(tester, vm);
      await fillFirst(tester);
      await next(tester);
      expect(find.text('Peso estimado'), findsOneWidget);
      await tester.tap(find.text('Atrás'));
      await tester.pumpAndSettle();
      expect(find.text('A-01'), findsOneWidget);
      expect(find.text('Criollo'), findsOneWidget);
      await next(tester);
      await next(tester);
      await tester.tap(find.text('Guardar animal'));
      await tester.pumpAndSettle();
      expect(vm.saved.single.code, 'A-01');
      expect(vm.saved.single.breed, 'Criollo');
      expect(vm.saved.single.weight, isNull);
      expect(vm.saved.single.paddockId, isNull);
      expect(vm.saved.single.name, isNull);
    },
  );
  for (final value in ['-1', 'abc', 'NaN', 'Infinity', '12,5', '12.5']) {
    testWidgets('weight navigation <$value>', (tester) async {
      final vm = RegistrationVm();
      await mount(tester, vm);
      await fillFirst(tester);
      await next(tester);
      await tester.enterText(find.byType(TextFormField), value);
      await next(tester);
      final valid = value.startsWith('12');
      expect(
        find.text('Confirma los datos'),
        valid ? findsOneWidget : findsNothing,
      );
      if (!valid) expect(find.textContaining('peso numérico'), findsOneWidget);
      expect(vm.saved, isEmpty);
    });
  }
  testWidgets(
    'final validation checks unmounted code and redirects without saving',
    (tester) async {
      final vm = RegistrationVm();
      await mount(tester, vm);
      await fillFirst(tester);
      final controller = tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!;
      await next(tester);
      await next(tester);
      controller.text = '   ';
      await tester.tap(find.text('Guardar animal'));
      await tester.pumpAndSettle();
      expect(find.text('Ingresa un código o arete'), findsOneWidget);
      expect(vm.saved, isEmpty);
    },
  );
  testWidgets('final validation redirects to unmounted invalid weight', (
    tester,
  ) async {
    final vm = RegistrationVm();
    await mount(tester, vm);
    await fillFirst(tester);
    await next(tester);
    final controller = tester
        .widget<TextFormField>(find.byType(TextFormField))
        .controller!;
    await next(tester);
    controller.text = '-5';
    await tester.tap(find.text('Guardar animal'));
    await tester.pumpAndSettle();
    expect(find.textContaining('peso numérico'), findsOneWidget);
    expect(vm.saved, isEmpty);
  });
}

Future<void> mount(
  WidgetTester tester,
  RegistrationVm vm, {
  Animal? animal,
}) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      localFormRecordsProvider(
        'animals',
      ).overrideWith((ref) => Stream.value([])),
      animalViewModelProvider.overrideWith(() => vm),
      paddockViewModelProvider.overrideWith(EmptyPaddocks.new),
    ],
  );
  addTearDown(container.dispose);
  await container.read(paddockViewModelProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: AnimalFormScreen(animal: animal)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> next(WidgetTester tester) async {
  tester.testTextInput.hide();
  await tester.tap(find.text('Siguiente'));
  await tester.pumpAndSettle();
}

Future<void> fillFirst(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, 'A-01');
  await tester.tap(find.widgetWithText(ChoiceChip, 'Toro'));
  await tester.enterText(
    find.descendant(
      of: find.byType(BreedAutocompleteField),
      matching: find.byType(TextFormField),
    ),
    'Criollo',
  );
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<BreedAutocompleteField>(find.byType(BreedAutocompleteField))
        .controller
        .text,
    'Criollo',
  );
}
