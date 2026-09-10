import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_remote_datasource.dart';
import 'package:mi_finca_app/features/animals/data/repositories/animal_repository_impl.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/animals/domain/repositories/animal_repository.dart';
import 'package:mi_finca_app/features/animals/domain/usecases/move_animal.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/services/paddock_operational_status.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnimalState {
  const AnimalState({this.animals = const [], this.movements = const []});

  final List<Animal> animals;
  final List<Movement> movements;

  AnimalState copyWith({List<Animal>? animals, List<Movement>? movements}) =>
      AnimalState(
        animals: animals ?? this.animals,
        movements: movements ?? this.movements,
      );
}

final animalLocalDataSourceProvider = Provider(
  (ref) => AnimalLocalDataSource(ref.watch(databaseProvider)),
);

final animalRemoteDataSourceProvider = Provider(
  (ref) => AnimalRemoteDataSource(Supabase.instance.client),
);

final animalRepositoryProvider = Provider<AnimalRepository>(
  (ref) => AnimalRepositoryImpl(
    local: ref.watch(animalLocalDataSourceProvider),
    remote: ref.watch(animalRemoteDataSourceProvider),
  ),
);

final moveAnimalProvider = Provider(
  (ref) => MoveAnimal(ref.watch(animalRepositoryProvider)),
);

final animalViewModelProvider =
    AsyncNotifierProvider<AnimalViewModel, AnimalState>(AnimalViewModel.new);

class AnimalViewModel extends AsyncNotifier<AnimalState> {
  @override
  Future<AnimalState> build() async {
    final repository = ref.watch(animalRepositoryProvider);

    return AnimalState(
      animals: await repository.getAll(),
      movements: await repository.getMovements(),
    );
  }

  Future<void> save(Animal animal) async {
    await ref.read(animalRepositoryProvider).save(animal);

    final items = [...state.requireValue.animals];
    final index = items.indexWhere((item) => item.id == animal.id);

    if (index < 0) {
      items.insert(0, animal);
    } else {
      items[index] = animal;
    }

    state = AsyncData(state.requireValue.copyWith(animals: items));

    unawaited(ref.read(syncViewModelProvider.notifier).syncPendingIfOnline());
  }

  Future<void> move(
    Animal animal,
    String destinationId,
    DateTime date, {
    int? plannedGrazingDays,
  }) async {
    await moveMany(
      [animal],
      destinationId,
      date,
      plannedGrazingDays: plannedGrazingDays,
    );
  }

  Future<int> moveMany(
    List<Animal> selectedAnimals,
    String destinationId,
    DateTime date, {
    int? plannedGrazingDays,
  }) async {
    final movableAnimals = selectedAnimals
        .where((animal) => animal.paddockId != destinationId)
        .toList();
    if (movableAnimals.isEmpty) return 0;

    final currentAnimals = state.requireValue.animals;
    final paddocks = ref.read(paddockViewModelProvider).requireValue;
    final destination = paddocks.firstWhere(
      (paddock) => paddock.id == destinationId,
    );
    if (!PaddockOperationalStatus.calculate(
      destination,
      referenceDate: date,
    ).canReceiveAnimals) {
      throw StateError('El potrero destino todavía no puede recibir animales.');
    }
    final destinationWasEmpty = !currentAnimals.any(
      (animal) => animal.paddockId == destinationId,
    );
    if (destinationWasEmpty && plannedGrazingDays == null) {
      throw const FormatException(
        'Indica los días de uso planeado para el potrero destino.',
      );
    }

    final results = <({Animal animal, Movement movement})>[];
    final moveAnimal = ref.read(moveAnimalProvider);
    final movedIds = movableAnimals.map((animal) => animal.id).toSet();
    final finalAnimals = currentAnimals
        .map(
          (animal) => movedIds.contains(animal.id)
              ? animal.copyWith(paddockId: destinationId)
              : animal,
        )
        .toList();
    final affectedOriginIds = movableAnimals
        .map((animal) => animal.paddockId)
        .whereType<String>()
        .where((id) => id != destinationId)
        .toSet();
    final updatedPaddocks = <Paddock>[
      for (final paddock in paddocks)
        if (affectedOriginIds.contains(paddock.id))
          _updatedOriginPaddock(
            paddock,
            hasAnimals: finalAnimals.any(
              (animal) => animal.paddockId == paddock.id,
            ),
            movementDate: date,
          ),
      _updatedDestinationPaddock(
        destination,
        wasEmpty: destinationWasEmpty,
        movementDate: date,
        plannedGrazingDays: plannedGrazingDays,
      ),
    ];

    await ref.read(databaseProvider).runInTransaction(() async {
      for (final animal in movableAnimals) {
        results.add(await moveAnimal(animal, destinationId, date));
      }
      final paddockRepository = ref.read(paddockRepositoryProvider);
      for (final paddock in updatedPaddocks) {
        await paddockRepository.save(paddock);
      }
    });

    final movedById = {for (final result in results) result.animal.id: result};
    final animals = state.requireValue.animals
        .map((item) => movedById[item.id]?.animal ?? item)
        .toList();
    final movements = [
      ...results.map((result) => result.movement),
      ...state.requireValue.movements,
    ];

    state = AsyncData(
      state.requireValue.copyWith(animals: animals, movements: movements),
    );
    ref
        .read(paddockViewModelProvider.notifier)
        .applyPersistedMovementUpdates(updatedPaddocks);

    unawaited(ref.read(syncViewModelProvider.notifier).syncPendingIfOnline());

    return results.length;
  }

  Future<void> reload() async {
    final repository = ref.read(animalRepositoryProvider);

    state = AsyncData(
      AnimalState(
        animals: await repository.getAll(),
        movements: await repository.getMovements(),
      ),
    );
  }
}

Paddock _updatedOriginPaddock(
  Paddock paddock, {
  required bool hasAnimals,
  required DateTime movementDate,
}) {
  if (hasAnimals) {
    return paddock.copyWith(status: 'En uso', updatedAt: DateTime.now());
  }

  return Paddock(
    id: paddock.id,
    name: paddock.name,
    areaHectares: paddock.areaHectares,
    pastureType: paddock.pastureType,
    requiredRestDays: paddock.requiredRestDays,
    rotationOrder: paddock.rotationOrder,
    status: 'Descansando',
    lastGrazingEndDate: movementDate,
    createdAt: paddock.createdAt,
    updatedAt: DateTime.now(),
  );
}

Paddock _updatedDestinationPaddock(
  Paddock paddock, {
  required bool wasEmpty,
  required DateTime movementDate,
  required int? plannedGrazingDays,
}) {
  return Paddock(
    id: paddock.id,
    name: paddock.name,
    areaHectares: paddock.areaHectares,
    pastureType: paddock.pastureType,
    requiredRestDays: paddock.requiredRestDays,
    rotationOrder: paddock.rotationOrder,
    grazingStartDate: wasEmpty ? movementDate : paddock.grazingStartDate,
    plannedGrazingDays: wasEmpty
        ? plannedGrazingDays
        : paddock.plannedGrazingDays,
    status: 'En uso',
    lastGrazingEndDate: null,
    createdAt: paddock.createdAt,
    updatedAt: DateTime.now(),
  );
}
