import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/data/repositories/animal_repository_impl.dart';
import 'package:mi_finca_app/features/animals/domain/repositories/animal_repository.dart';
import 'package:mi_finca_app/features/animals/domain/usecases/move_animal.dart';

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
final animalRepositoryProvider = Provider<AnimalRepository>(
  (ref) => AnimalRepositoryImpl(ref.watch(animalLocalDataSourceProvider)),
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
