import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Test doubles for plugins already used by the app; no native camera is opened.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:mi_finca_app/core/network/network_status.dart';
import 'package:mi_finca_app/core/validation/local_form_duplicates.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_patch.dart';
import 'package:mi_finca_app/features/animals/presentation/screens/animal_screens.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_photo_cache_provider.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/animals/presentation/widgets/animal_photo_avatar.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';

import 'animal_registration_test.dart'
    show RegistrationVm, EmptyPaddocks, next, fillFirst;

class _PhotoVm extends RegistrationVm {
  final selectedPhotos = <String?>[];
  Animal? existing;

  @override
  Future<AnimalState> build() async =>
      AnimalState(animals: [if (existing != null) existing!]);

  @override
  Future<void> edit(
    String id,
    AnimalPatch patch, {
    String? selectedPhoto,
  }) async {
    selectedPhotos.add(selectedPhoto);
    await super.edit(id, patch, selectedPhoto: selectedPhoto);
  }
}

class _Picker extends ImagePickerPlatform {
  String? result;
  final sources = <ImageSource>[];

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    sources.add(source);
    return result == null ? null : XFile(result!);
  }
}

class _Directories extends PathProviderPlatform {
  _Directories(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late Directory directory;
  late File image;
  late _Picker picker;
  late ImagePickerPlatform originalPicker;
  late PathProviderPlatform originalDirectories;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('animal-form-photo');
    image = File('${directory.path}/source.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
        ),
      );
    originalPicker = ImagePickerPlatform.instance;
    originalDirectories = PathProviderPlatform.instance;
    picker = _Picker();
    ImagePickerPlatform.instance = picker;
    PathProviderPlatform.instance = _Directories(directory.path);
  });
  tearDown(() {
    ImagePickerPlatform.instance = originalPicker;
    PathProviderPlatform.instance = originalDirectories;
    directory.deleteSync(recursive: true);
  });

  Animal animal({String? local, String? remote}) => Animal(
    id: 'a',
    code: 'A',
    type: 'Vaca',
    breed: 'Criollo',
    sex: 'Hembra',
    localPhotoPath: local,
    remotePhotoPath: remote,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  Future<void> mount(
    WidgetTester tester,
    RegistrationVm vm, {
    Animal? value,
  }) async {
    final container = ProviderContainer(
      overrides: [
        localFormRecordsProvider(
          'animals',
        ).overrideWith((ref) => Stream.value([])),
        animalViewModelProvider.overrideWith(() => vm),
        paddockViewModelProvider.overrideWith(EmptyPaddocks.new),
        animalPhotoCacheProvider.overrideWith((ref, key) async => null),
        photoNetworkAllowedProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    await container.read(paddockViewModelProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: AnimalFormScreen(animal: value)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settlePhoto(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
  }

  for (final state in ['new', 'empty', 'local', 'missing', 'remote']) {
    testWidgets('photo label reflects $state and both targets open options', (
      tester,
    ) async {
      final value = switch (state) {
        'new' => null,
        'local' => animal(local: image.path),
        'missing' => animal(local: '${directory.path}/missing.png'),
        'remote' => animal(remote: 'owner/a/photo.png'),
        _ => animal(),
      };
      await mount(tester, RegistrationVm(), value: value);
      final label = state == 'local' || state == 'remote'
          ? 'Cambiar foto'
          : 'Agregar foto del animal';
      expect(find.text(label), findsOneWidget);
      final avatar = find.byType(AnimalPhotoAvatar);
      expect(tester.widget<AnimalPhotoAvatar>(avatar).radius, 62);
      // Tap the avatar's edge so an existing retry button cannot intercept it.
      await tester.tapAt(tester.getTopLeft(avatar) + const Offset(10, 62));
      await tester.pumpAndSettle();
      expect(find.text('Tomar foto'), findsOneWidget);
      expect(find.text('Elegir de galería'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('Tomar foto'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(picker.sources, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'selection, replacement and cancellation preserve draft and saved photo',
    (tester) async {
      final vm = _PhotoVm();
      await mount(tester, vm, value: animal());
      await tester.enterText(find.byType(TextFormField).first, '001');
      await tester.enterText(find.byType(TextFormField).at(1), 'Coco');
      String? previous;
      for (final option in [
        'Tomar foto',
        'Elegir de galería',
        'Elegir de galería',
      ]) {
        picker.result = previous != null && picker.sources.length == 2
            ? null
            : image.path;
        await tester.ensureVisible(find.byType(AnimalPhotoAvatar));
        await tester.tap(
          find.text(
            previous == null ? 'Agregar foto del animal' : 'Cambiar foto',
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text(option));
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await settlePhoto(tester);
        final current = tester
            .widget<AnimalPhotoAvatar>(find.byType(AnimalPhotoAvatar))
            .localPhotoPath;
        expect(find.text('Cambiar foto'), findsOneWidget);
        if (picker.result == null) {
          expect(current, previous);
        } else {
          expect(current, isNot(previous));
          expect(File(current!).existsSync(), isTrue);
        }
        previous = current;
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).first)
              .controller!
              .text,
          '001',
        );
      }
      expect(picker.sources, [
        ImageSource.camera,
        ImageSource.gallery,
        ImageSource.gallery,
      ]);
      await next(tester);
      await next(tester);
      await tester.tap(find.text('Guardar animal'));
      await tester.pumpAndSettle();
      expect(vm.patches.single.localValues, {'code': '001', 'name': 'Coco'});
      expect(vm.selectedPhotos.single, previous);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cancelled native selection leaves edit untouched on small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final vm = _PhotoVm();
      await mount(tester, vm, value: animal(local: image.path));
      await tester.tap(find.text('Cambiar foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegir de galería'));
      await tester.pumpAndSettle();
      expect(find.text('Cambiar foto'), findsOneWidget);
      await next(tester);
      await next(tester);
      await tester.tap(find.text('Guardar animal'));
      await tester.pumpAndSettle();
      expect(vm.patches.single.localValues, isEmpty);
      expect(vm.selectedPhotos.single, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('new animal saves selected photo without losing draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final vm = RegistrationVm();
    await mount(tester, vm);
    await fillFirst(tester);
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Agregar foto del animal'));
    await tester.tap(find.text('Agregar foto del animal'));
    await tester.pumpAndSettle();
    picker.result = image.path;
    await tester.runAsync(() async {
      await tester.tap(find.text('Elegir de galería'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await settlePhoto(tester);
    expect(find.text('Cambiar foto'), findsOneWidget);
    final selected = tester
        .widget<AnimalPhotoAvatar>(find.byType(AnimalPhotoAvatar))
        .localPhotoPath;
    await next(tester);
    await next(tester);
    await tester.tap(find.text('Guardar animal'));
    await tester.pumpAndSettle();
    expect(vm.saved.single.localPhotoPath, selected);
    expect(vm.saved.single.code, 'A-01');
    expect(vm.saved.single.breed, 'Criollo');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('detail has no form photo captions', (tester) async {
    final value = animal(local: image.path);
    final vm = _PhotoVm()..existing = value;
    await mount(tester, vm, value: value);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AnimalFormScreen)),
    );
    await container.read(animalViewModelProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: AnimalDetailScreen(animalId: value.id)),
      ),
    );
    await settlePhoto(tester);
    expect(find.byType(AnimalPhotoAvatar), findsOneWidget);
    expect(find.text('Cambiar foto'), findsNothing);
    expect(find.text('Agregar foto del animal'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
