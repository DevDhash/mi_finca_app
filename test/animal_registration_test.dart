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
    expect(find.text('Selecciona el sexo del animal'), findsOneWidget);
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
        await tester.tap(find.widgetWithText(ChoiceChip, 'Vaca'));
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
      if (missing != 'sex') await tester.tap(find.text('Hembra'));
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

Future<void> mount(WidgetTester tester, RegistrationVm vm) async {
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
      child: const MaterialApp(home: AnimalFormScreen()),
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
  await tester.tap(find.text('Macho'));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<BreedAutocompleteField>(find.byType(BreedAutocompleteField))
        .controller
        .text,
    'Criollo',
  );
}
