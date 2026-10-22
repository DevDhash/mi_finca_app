import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/animals/domain/constants/cattle_breeds.dart';
import 'package:mi_finca_app/features/animals/presentation/utils/breed_search.dart';
import 'package:mi_finca_app/features/animals/presentation/widgets/breed_autocomplete_field.dart';

void main() {
  test('searches prefixes, case, accents, combining marks and aliases', () {
    expect(searchCattleBreeds('BRA'), containsAll(['Brahman', 'Brangus']));
    expect(searchCattleBreeds(' bra '), searchCattleBreeds('BRA'));
    expect(searchCattleBreeds('pardo suizo'), ['Brown Swiss']);
    expect(searchCattleBreeds('Nellore'), ['Nelore']);
    expect(searchCattleBreeds('gir'), contains('Gyr'));
    expect(searchCattleBreeds('guzera'), ['Guzerat']);
    expect(searchCattleBreeds('GUZERÁ'), ['Guzerat']);
    expect(searchCattleBreeds('guzera\u0301'), ['Guzerat']);
    expect(searchCattleBreeds('stein'), ['Holstein']);
    expect(searchCattleBreeds('  '), isEmpty);
    expect(searchCattleBreeds('Mi cruce especial'), isEmpty);
  });

  test('catalog contains exactly the 31 approved primary options', () {
    expect(cattleBreeds.map((breed) => breed.name).toList(), [
      'Holstein',
      'Brown Swiss',
      'Jersey',
      'Ayrshire',
      'Guernsey',
      'Brahman',
      'Brahman Rojo',
      'Brahman Gris',
      'Nelore',
      'Nelore Mocho',
      'Gyr',
      'Guzerat',
      'Indubrasil',
      'Sahiwal',
      'Angus',
      'Hereford',
      'Brangus',
      'Braford',
      'Charolais',
      'Limousin',
      'Simmental',
      'Fleckvieh',
      'Braunvieh',
      'Normando',
      'Senepol',
      'Santa Gertrudis',
      'Beefmaster',
      'Girolando',
      'Criollo',
      'Wagyu',
      'Raza no especificada',
    ]);
    expect(cattleBreeds.length, 31);
    expect(cattleBreeds.map((breed) => breed.name).toSet().length, 31);
    expect(searchCattleBreeds('Criollo peruano'), ['Criollo']);
    expect(searchCattleBreeds('Brahman'), [
      'Brahman',
      'Brahman Rojo',
      'Brahman Gris',
    ]);
    expect(searchCattleBreeds('Nelore'), ['Nelore', 'Nelore Mocho']);
    for (final query in [
      'Raza no especificada',
      'Desconocida',
      'Sin especificar',
    ]) {
      expect(searchCattleBreeds(query), ['Raza no especificada']);
    }
  });

  test('catalog names and aliases do not collide across entries', () {
    final owners = <String, String>{};
    for (final breed in cattleBreeds) {
      for (final name in [breed.name, ...breed.aliases]) {
        final normalized = normalizeBreedSearch(name);
        expect(normalized, isNotEmpty);
        expect(owners[normalized], anyOf(isNull, breed.name));
        owners[normalized] = breed.name;
      }
    }
    final matches = searchCattleBreeds('s');
    expect(matches.length, matches.toSet().length);
  });

  Future<TextEditingController> mount(
    WidgetTester tester, {
    String initial = '',
    ValueChanged<String>? changed,
  }) async {
    final controller = TextEditingController(text: initial);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              const SizedBox(height: 450),
              BreedAutocompleteField(
                controller: controller,
                onChanged: changed ?? (_) {},
              ),
              const SizedBox(height: 32),
              const TextField(key: ValueKey('other-field')),
            ],
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byType(TextFormField),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('touch selection notifies caller and closes options', (
    tester,
  ) async {
    final changes = <String>[];
    final controller = await mount(tester, changed: changes.add);
    await tester.enterText(find.byType(TextFormField), 'Bra');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brangus'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Brangus');
    expect(changes.last, 'Brangus');
    expect(find.byKey(const ValueKey('breed-suggestions')), findsNothing);
  });

  for (final option in cattleBreeds) {
    testWidgets('can explicitly select ${option.name}', (tester) async {
      final controller = await mount(tester);
      await tester.enterText(find.byType(TextFormField), option.name);
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('breed-suggestions'));
      await tester.tap(
        find.descendant(of: menu, matching: find.text(option.name)),
      );
      await tester.pumpAndSettle();
      expect(controller.text, option.name);
      expect(menu, findsNothing);
    });
  }

  testWidgets('Done preserves custom text even when there are matches', (
    tester,
  ) async {
    final controller = await mount(tester);
    await tester.enterText(find.byType(TextFormField), 'Bra');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, 'Bra');
    expect(find.byKey(const ValueKey('breed-suggestions')), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'Mi raza local');
    await tester.pumpAndSettle();
    expect(controller.text, 'Mi raza local');
    expect(find.byKey(const ValueKey('breed-suggestions')), findsNothing);
  });

  testWidgets('existing text remains untouched and empty text is invalid', (
    tester,
  ) async {
    final changes = <String>[];
    final controller = await mount(
      tester,
      initial: 'Raza anterior',
      changed: changes.add,
    );
    expect(controller.text, 'Raza anterior');
    expect(changes, isEmpty);
    await tester.enterText(find.byType(TextFormField), '   ');
    final state = tester.state<FormFieldState<String>>(
      find.byType(TextFormField),
    );
    expect(state.validate(), isFalse);
    await tester.pump();
    expect(find.text('Ingresa la raza'), findsOneWidget);
  });

  for (final size in [const Size(390, 720), const Size(720, 390)]) {
    testWidgets('options stay above keyboard and scroll on $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      await mount(tester);
      await tester.enterText(find.byType(TextFormField), 's');
      await tester.pumpAndSettle();
      final keyboard = size.height > 500 ? 300.0 : 160.0;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('breed-suggestions'));
      expect(menu, findsOneWidget);
      final rect = tester.getRect(menu);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(size.height - keyboard));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.height, lessThanOrEqualTo(240));
      final options = find.descendant(
        of: menu,
        matching: find.byType(Scrollable),
      );
      final lastOption = find.text(searchCattleBreeds('s').last);
      await tester.scrollUntilVisible(lastOption, 100, scrollable: options);
      await tester.pumpAndSettle();
      expect(lastOption.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
