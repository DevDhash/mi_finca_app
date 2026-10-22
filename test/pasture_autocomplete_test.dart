import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/paddocks/domain/constants/pasture_types.dart';
import 'package:mi_finca_app/features/paddocks/presentation/utils/pasture_search.dart';
import 'package:mi_finca_app/features/paddocks/presentation/widgets/pasture_autocomplete_field.dart';

void main() {
  test('approved catalog and search preserve distinct cultivars', () {
    expect(
      pastureTypes.map((p) => p.name).toList(),
      containsAll([
        'Setaria',
        'Brachiaria',
        'Brachiaria brizantha',
        'Brachiaria decumbens',
        'Brachiaria humidicola',
        'Brachiaria ruziziensis',
        'Marandú',
        'Mombasa',
        'Tanzania',
        'Pasto Guinea',
        'Pasto Elefante',
        'Maralfalfa',
        'King Grass',
        'Camerún',
        'Cuba 22',
        'Pasto Guatemala',
        'Ryegrass inglés',
        'Ryegrass italiano',
        'Dactylis glomerata',
        'Festuca',
        'Kikuyo',
        'Trébol blanco',
        'Trébol rojo',
        'Alfalfa',
        'Centrosema',
        'Kudzu tropical',
        'Stylosanthes',
        'Maní forrajero',
        'Pasto Estrella',
        'Pasto Bermuda',
        'Pasto Pangola',
        'Pastura no especificada',
      ]),
    );
    expect(pastureTypes.length, greaterThan(32));
    expect(pastureTypes.map((p) => p.name).toSet().length, pastureTypes.length);
    expect(searchPastureTypes('Setarea'), ['Setaria']);
    expect(
      searchPastureTypes('Bra'),
      containsAll([
        'Brachiaria brizantha',
        'Brachiaria decumbens',
        'Brachiaria humidicola',
        'Brachiaria ruziziensis',
      ]),
    );
    expect(searchPastureTypes('Mar').take(2).toList(), [
      'Maralfalfa',
      'Marandú',
    ]);
    expect(searchPastureTypes('Trebol'), [
      'Trébol alejandrino',
      'Trébol blanco',
      'Trébol persa',
      'Trébol rojo',
      'Trébol subterráneo',
    ]);
    expect(searchPastureTypes('desconocida'), ['Pastura no especificada']);
    expect(searchPastureTypes('  TRÉBOL '), searchPastureTypes('trebol'));
    expect(searchPastureTypes('tre\u0301bol'), searchPastureTypes('trebol'));
    expect(searchPastureTypes('Mombaça'), ['Mombasa']);
    expect(
      searchPastureTypes('Panicum maximum'),
      containsAll(['Pasto Guinea', 'Mombasa', 'Tanzania']),
    );
    expect(searchPastureTypes('Megathyrsus maximus cv. Tanzania'), [
      'Tanzania',
    ]);
    expect(searchPastureTypes('alfalfa').first, 'Alfalfa');
    expect(searchPastureTypes('   '), isEmpty);
    expect(searchPastureTypes('Mi mezcla local'), isEmpty);
    for (final pasture in pastureTypes) {
      for (final alias in pasture.aliases) {
        expect(searchPastureTypes(alias), contains(pasture.name));
      }
    }
  });

  test(
    'catalog is alphabetical and search keeps sorted prefix/partial groups',
    () {
      String orderKey(String name) =>
          normalizePastureSearch(name.replaceAll('ñ', 'n\uffff'));
      final names = pastureTypes.map((p) => p.name).toList();
      final sorted = [...names]
        ..sort((a, b) => orderKey(a).compareTo(orderKey(b)));
      expect(names, sorted);
      final normalizedNames = names.map(normalizePastureSearch).toList();
      expect(normalizedNames.every((name) => name.isNotEmpty), isTrue);
      expect(normalizedNames.toSet().length, names.length);
      for (final pasture in pastureTypes) {
        final aliases = pasture.aliases.map(normalizePastureSearch).toList();
        expect(aliases.toSet().length, aliases.length, reason: pasture.name);
      }
      const query = 'bra';
      final prefix = pastureTypes
          .where(
            (p) => [
              p.name,
              ...p.aliases,
            ].any((key) => normalizePastureSearch(key).startsWith(query)),
          )
          .map((p) => p.name)
          .toList();
      final matches = searchPastureTypes(query);
      expect(matches.take(prefix.length).toList(), prefix);
      final partial = matches.skip(prefix.length).toList();
      expect(
        partial,
        [...partial]..sort((a, b) => orderKey(a).compareTo(orderKey(b))),
      );
    },
  );

  test(
    'synonyms identify one owner while distinct cultivars stay independent',
    () {
      final synonyms = <String, String>{
        'Toledo': 'Xaraés',
        'Urochloa brizantha cv. Toledo': 'Xaraés',
        'Festuca dolichophylla': 'Chillihua',
        'Maní forrajero rastrero': 'Maní forrajero',
        'Napier': 'Pasto Elefante',
        'Brachiaria mutica': 'Pasto Pará',
        'Urochloa mutica': 'Pasto Pará',
        'Urochloa dictyoneura': 'Brachiaria dictyoneura',
        'Urochloa humidicola cv. Llanero': 'Llanero',
        'INIA 910 Kumymarca': 'Ryegrass Kumymarca',
        'Lolium perenne cv. Nui': 'Ryegrass Nui',
        'Phalaris aquatica': 'Falaris Harding',
        'Trifolium subterraneum': 'Trébol subterráneo',
        'Sorghum bicolor': 'Sorgo forrajero',
        'Zea mays': 'Maíz chala',
        'OM-22': 'Cuba OM-22',
      };
      for (final entry in synonyms.entries) {
        expect(searchPastureTypes(entry.key), [entry.value]);
      }
      expect(searchPastureTypes('Sin especificar'), [
        'Pastura no especificada',
      ]);
      expect(
        pastureTypes
            .singleWhere((p) => p.name == 'Pastura no especificada')
            .aliases,
        ['Sin especificar', 'Pastura desconocida'],
      );
      expect(
        pastureTypes.map((p) => p.name),
        containsAll([
          'Mulato',
          'Mulato II',
          'Cayman',
          'Cobra',
          'Mavuno',
          'Brachiaria brizantha',
          'Marandú',
          'Xaraés',
          'Piatã',
          'Paiaguás',
          'Brachiaria dictyoneura',
          'Brachiaria humidicola',
          'Llanero',
          'Tully',
          'Pasto Guinea',
          'Mombasa',
          'Tanzania',
          'Massai',
          'Colonião',
          'Cuba 22',
          'Cuba OM-22',
          'CT-115',
          'CT-169',
        ]),
      );
      for (final name in [
        'Grama dulce',
        'Pasto Gramalote',
        'Pasto Azul',
        'Ichu',
        'Crespillo',
      ]) {
        expect(
          pastureTypes.singleWhere((p) => p.name == name).aliases,
          isEmpty,
        );
      }
    },
  );

  test('all 98 requested additions remain searchable after deduplication', () {
    const requested = <String>[
      'Setaria Kazungula',
      'Setaria Narok',
      'Brachiaria dictyoneura',
      'Pasto Pará',
      'Xaraés',
      'Piatã',
      'Paiaguás',
      'Toledo',
      'Llanero',
      'Tully',
      'Mulato',
      'Mulato II',
      'Cayman',
      'Cobra',
      'Mavuno',
      'Massai',
      'Zuri',
      'Aruana',
      'Tobiatã',
      'Gatton Panic',
      'Colonião',
      'Tifton 85',
      'Coastcross',
      'Pasto Alemán',
      'Pasto Tanner',
      'Pasto Angleton',
      'Pasto Jaragua',
      'Pasto Gordura',
      'Pasto Carimagua',
      'Pasto Bahía',
      'Pasto Gramalote',
      'Grama dulce',
      'Ryegrass híbrido',
      'Ryegrass Cajamarquino',
      'Ryegrass Kumymarca',
      'Ryegrass Nui',
      'Ryegrass Tama',
      'Festuca alta',
      'Festuca de pradera',
      'Falaris',
      'Falaris Harding',
      'Cebadilla criolla',
      'Pasto Azul',
      'Agrostis',
      'Holcus',
      'Bromus',
      'Trébol subterráneo',
      'Trébol persa',
      'Trébol alejandrino',
      'Maní forrajero rastrero',
      'Centrosema macrocarpum',
      'Stylosanthes guianensis',
      'Stylosanthes capitata',
      'Stylosanthes macrocephala',
      'Desmodium ovalifolium',
      'Desmodium intortum',
      'Desmodium uncinatum',
      'Calopogonio',
      'Siratro',
      'Lablab',
      'Vicia común',
      'Vicia vellosa',
      'Lotus corniculatus',
      'Lotus pedunculatus',
      'Ichu',
      'Chillihua',
      'Crespillo',
      'Calamagrostis',
      'Calamagrostis rigida',
      'Festuca dolichophylla',
      'Festuca orthophylla',
      'Muhlenbergia',
      'Muhlenbergia fastigiata',
      'Poa altoandina',
      'Poa candamoana',
      'Bromus lanatus',
      'Nassella',
      'Distichia',
      'Carex',
      'Juncus',
      'Lachemilla',
      'Eleocharis',
      'Scirpus',
      'Plantago rigida',
      'Werneria',
      'Elefante morado',
      'Cuba OM-22',
      'CT-115',
      'CT-169',
      'Caña forrajera',
      'Sorgo forrajero',
      'Sorgo Sudán',
      'Maíz chala',
      'Avena forrajera',
      'Cebada forrajera',
      'Centeno forrajero',
      'Triticale',
      'Trigo forrajero',
    ];
    for (final name in requested) {
      expect(searchPastureTypes(name), isNotEmpty, reason: name);
    }
    expect(pastureTypes.length, 127);
  });

  test('catalog names and aliases do not collide across entries', () {
    final owners = <String, String>{};
    for (final pasture in pastureTypes) {
      for (final name in [pasture.name, ...pasture.aliases]) {
        final normalized = normalizePastureSearch(name);
        expect(normalized, isNotEmpty);
        expect(owners[normalized], anyOf(isNull, pasture.name));
        owners[normalized] = pasture.name;
      }
    }
    final matches = searchPastureTypes('s');
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
              PastureAutocompleteField(
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
    await tester.enterText(find.byType(TextFormField), 'Mar');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marandú'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Marandú');
    expect(changes.last, 'Marandú');
    expect(find.byKey(const ValueKey('pasture-suggestions')), findsNothing);
  });

  for (final option in pastureTypes) {
    testWidgets('can explicitly select ${option.name}', (tester) async {
      final controller = await mount(tester);
      await tester.enterText(find.byType(TextFormField), option.name);
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('pasture-suggestions'));
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
    await tester.enterText(find.byType(TextFormField), 'Mar');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, 'Mar');
    expect(find.byKey(const ValueKey('pasture-suggestions')), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'Mi mezcla local');
    await tester.pumpAndSettle();
    expect(controller.text, 'Mi mezcla local');
    expect(find.byKey(const ValueKey('pasture-suggestions')), findsNothing);
  });

  testWidgets('existing text remains untouched and empty text is optional', (
    tester,
  ) async {
    final changes = <String>[];
    final controller = await mount(
      tester,
      initial: 'Setarea histórica',
      changed: changes.add,
    );
    expect(controller.text, 'Setarea histórica');
    expect(changes, isEmpty);
    await tester.enterText(find.byType(TextFormField), '   ');
    final state = tester.state<FormFieldState<String>>(
      find.byType(TextFormField),
    );
    expect(state.validate(), isTrue);
    await tester.pump();
    expect(changes.last, '   ');
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
      final menu = find.byKey(const ValueKey('pasture-suggestions'));
      expect(menu, findsOneWidget);
      final rect = tester.getRect(menu);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(size.height - keyboard));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.height, lessThanOrEqualTo(240));
      final list = tester.widget<ListView>(
        find.descendant(of: menu, matching: find.byType(ListView)),
      );
      expect(list.itemExtent, 48);
      final options = find.descendant(
        of: menu,
        matching: find.byType(Scrollable),
      );
      final lastOption = find.text(searchPastureTypes('s').last);
      await tester.scrollUntilVisible(
        lastOption,
        100,
        scrollable: options,
        maxScrolls: 200,
      );
      await tester.pumpAndSettle();
      expect(lastOption.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
