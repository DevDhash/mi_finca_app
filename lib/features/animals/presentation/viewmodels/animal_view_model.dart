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

  Future<void> move(Animal animal, String destinationId, DateTime date) async {
    final result = await ref.read(moveAnimalProvider)(
      animal,
      destinationId,
      date,
    );

    final animals = state.requireValue.animals
        .map((item) => item.id == result.animal.id ? result.animal : item)
        .toList();

    state = AsyncData(
      state.requireValue.copyWith(
        animals: animals,
        movements: [result.movement, ...state.requireValue.movements],
      ),
    );

    unawaited(ref.read(syncViewModelProvider.notifier).syncPendingIfOnline());
  }

  Future<int> moveMany(
    List<Animal> selectedAnimals,
    String destinationId,
    DateTime date,
  ) async {
    final movableAnimals = selectedAnimals
        .where((animal) => animal.paddockId != destinationId)
        .toList();
    if (movableAnimals.isEmpty) return 0;

    final results = <({Animal animal, Movement movement})>[];
    final moveAnimal = ref.read(moveAnimalProvider);

    for (final animal in movableAnimals) {
      results.add(await moveAnimal(animal, destinationId, date));
    }

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
