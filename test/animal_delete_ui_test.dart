import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/repositories/animal_repository.dart';
import 'package:mi_finca_app/features/animals/presentation/screens/animal_screens.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/presentation/screens/paddock_screens.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/home/presentation/main_screens.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';
import 'package:mi_finca_app/features/farm/presentation/viewmodels/farm_view_model.dart';
import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';
import 'animal_deletion_test.dart' show deletionAnimal, deletionDate;

class UIAnimals extends AnimalViewModel {
  int deletes = 0;
  int moves = 0;
  Completer<void>? gate;
  AnimalDeletionResult result = AnimalDeletionResult.accepted;
  @override
  Future<AnimalState> build() async => AnimalState(animals: [deletionAnimal()]);
  void disappear() =>
      state = AsyncData(state.requireValue.copyWith(animals: []));
  @override
  Future<AnimalDeletionResult> deleteAnimal(String id) async {
    deletes++;
    await gate?.future;
    if (result == AnimalDeletionResult.accepted) disappear();
    return result;
  }

  @override
  Future<void> save(Animal animal) async {
    if (state.requireValue.animals.isEmpty) throw StateError('deleted');
  }

  @override
  Future<int> moveMany(
    List<Animal> selectedAnimals,
    String destinationId,
    DateTime date, {
    int? plannedGrazingDays,
  }) async {
    moves++;
    return selectedAnimals.length;
  }
}

class UIPaddocks extends PaddockViewModel {
  @override
  Future<List<Paddock>> build() async => [
    Paddock(
      id: 'p1',
      name: 'Planta 2',
      areaHectares: 1,
      status: 'En uso',
      createdAt: deletionDate,
      updatedAt: deletionDate,
    ),
    Paddock(
      id: 'p2',
      name: 'Destino',
      areaHectares: 1,
      createdAt: deletionDate,
      updatedAt: deletionDate,
    ),
  ];
}

class UIAuth extends AuthViewModel {
  @override
  Future<UserSession?> build() async =>
      const UserSession(id: 'owner', name: 'Ana', email: 'ana@example.test');
}

class UIFarm extends FarmViewModel {
  @override
  Future<Farm?> build() async =>
      const Farm(id: 'farm', name: 'Mi Finca', location: 'Lima');
}

class UISync extends SyncViewModel {
  @override
  Future<SyncState> build() async => const SyncState(isOnline: false);
}

void main() {
  late ProviderContainer container;
  late UIAnimals vm;
  setUp(() async {
    vm = UIAnimals();
    container = ProviderContainer(
      overrides: [
        animalViewModelProvider.overrideWith(() => vm),
        paddockViewModelProvider.overrideWith(UIPaddocks.new),
        authViewModelProvider.overrideWith(UIAuth.new),
        farmViewModelProvider.overrideWith(UIFarm.new),
        syncViewModelProvider.overrideWith(UISync.new),
        monthlyExpenseTotalProvider.overrideWithValue(0),
      ],
    );
    await container.read(animalViewModelProvider.future);
    await container.read(paddockViewModelProvider.future);
    await container.read(authViewModelProvider.future);
    await container.read(farmViewModelProvider.future);
    await container.read(syncViewModelProvider.future);
  });
  tearDown(() => container.dispose());
  Future<void> open(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => screen),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> dialog(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar animal'));
    await tester.pumpAndSettle();
  }

  testWidgets('cancel leaves animal and detail intact', (tester) async {
    await open(tester, const AnimalDetailScreen(animalId: 'a'));
    await dialog(tester);
    expect(find.text('¿Eliminar a Fifi?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(vm.deletes, 0);
    expect(find.byType(AnimalDetailScreen), findsOneWidget);
  });
  testWidgets(
    'confirm twice invokes once and closes once after local acceptance',
    (tester) async {
      vm.gate = Completer<void>();
      await open(tester, const AnimalDetailScreen(animalId: 'a'));
      await dialog(tester);
      final button = find.widgetWithText(FilledButton, 'Eliminar');
      final confirm = tester.widget<FilledButton>(button).onPressed!;
      confirm();
      confirm();
      await tester.pumpAndSettle();
      expect(vm.deletes, 1);
      expect(find.byType(AnimalDetailScreen), findsOneWidget);
      vm.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Abrir'), findsOneWidget);
      expect(find.text('Animal eliminado.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final result in [
    AnimalDeletionResult.needsVerification,
    AnimalDeletionResult.ownershipFailure,
  ]) {
    testWidgets('$result shows simple feedback and stays in detail', (
      tester,
    ) async {
      vm.result = result;
      await open(tester, const AnimalDetailScreen(animalId: 'a'));
      await dialog(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(find.byType(AnimalDetailScreen), findsOneWidget);
      expect(
        find.textContaining(
          result == AnimalDeletionResult.needsVerification
              ? 'No pudimos verificar'
              : 'La sesión cambió',
        ),
        findsOneWidget,
      );
    });
  }
  testWidgets('remote disappearance safely exits open detail', (tester) async {
    await open(tester, const AnimalDetailScreen(animalId: 'a'));
    vm.disappear();
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'editor above deleted detail catches save conflict without popping wrong route',
    (tester) async {
      await open(tester, const AnimalDetailScreen(animalId: 'a'));
      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();
      vm.disappear();
      await tester.pumpAndSettle();
      expect(find.byType(AnimalFormScreen), findsOneWidget);
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar animal'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se pudo guardar.'), findsOneWidget);
      expect(
        container.read(animalViewModelProvider).requireValue.animals,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('open individual movement tolerates disappeared animal', (
    tester,
  ) async {
    await open(tester, const MoveAnimalScreen(animalId: 'a'));
    vm.disappear();
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
    expect(vm.moves, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'batch prunes invalid selections and disables move when none remain',
    (tester) async {
      await open(tester, const MoveAnimalBatchScreen());
      await tester.ensureVisible(find.byType(Checkbox).first);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      vm.disappear();
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.byWidgetPredicate((w) => w is FilledButton).last,
      );
      expect(button.onPressed, isNull);
      expect(find.text('0 seleccionados'), findsOneWidget);
      expect(vm.moves, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('paddock count decreases to zero without changing En uso', (
    tester,
  ) async {
    await open(tester, const PaddockListScreen());
    expect(find.text('1 animales'), findsOneWidget);
    vm.disappear();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1 animales'), findsNothing);
    expect(find.text('0 animales'), findsOneWidget);
    expect(
      container.read(paddockViewModelProvider).requireValue.first.status,
      'En uso',
    );
  });
  testWidgets(
    'Home animal total decreases when local state loses the last animal',
    (tester) async {
      await open(tester, const DashboardScreen());
      expect(find.text('1'), findsOneWidget);
      vm.disappear();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1'), findsNothing);
      expect(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('Animales'),
                matching: find.byType(Column),
              )
              .first,
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('paddock detail removes animal and preserves grazing state', (
    tester,
  ) async {
    await open(tester, const PaddockDetailScreen(paddockId: 'p1'));
    expect(find.text('Animales asignados (1)'), findsOneWidget);
    vm.disappear();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Animales asignados (0)'), findsOneWidget);
    expect(find.text('Fifi'), findsNothing);
    expect(
      container.read(paddockViewModelProvider).requireValue.first.status,
      'En uso',
    );
  });
  testWidgets(
    'list and search omit deleted animal without a card trash action',
    (tester) async {
      await open(tester, const AnimalListScreen());
      expect(find.text('Fifi'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Fifi');
      vm.disappear();
      await tester.pumpAndSettle();
      expect(
        find.text('Fifi'),
        findsOneWidget,
      ); // search input only, no animal card
      expect(find.widgetWithText(ListTile, 'Fifi'), findsNothing);
    },
  );
}
