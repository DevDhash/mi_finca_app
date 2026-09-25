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
import 'package:mi_finca_app/features/sync/domain/repositories/sync_repository.dart';
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
    pullTombstones: () async {
      final sync = ref.read(syncRepositoryProvider);
      if (sync is TombstoneSyncRepository) await sync.pullRemoteTombstones();
    },
  ),
);

final moveAnimalProvider = Provider(
  (ref) => MoveAnimal(ref.watch(animalRepositoryProvider)),
);

final animalViewModelProvider =
    AsyncNotifierProvider<AnimalViewModel, AnimalState>(AnimalViewModel.new);

class AnimalViewModel extends AsyncNotifier<AnimalState> {
  int _localRead = 0;
  final _deletions = <String, Future<AnimalDeletionResult>>{};

  Future<void> _requestSync() async {
    try {
      await ref.read(syncViewModelProvider.notifier).syncPendingIfOnline();
    } catch (_) {
      // An accepted local change remains durable and retryable after network failure.
    }
  }

  Future<void> reloadLocal() async {
    final generation = ++_localRead;
    final items = await ref.read(animalRepositoryProvider).getLocal();
    if (!ref.mounted || generation != _localRead) return;
    state = AsyncData(
      (state.value ?? const AnimalState()).copyWith(animals: items),
    );
  }

  Future<AnimalDeletionResult> deleteAnimal(String id) =>
      _deletions.putIfAbsent(
        id,
        () => _deleteAnimal(id).whenComplete(() {
          _deletions.remove(id);
        }),
      );

  Future<AnimalDeletionResult> _deleteAnimal(String id) async {
    final result = await ref.read(animalRepositoryProvider).deleteAnimal(id);
    await reloadLocal();
    if (ref.mounted && result == AnimalDeletionResult.accepted) {
      unawaited(_requestSync());
    }
    return result;
  }

  @override
  Future<AnimalState> build() async {
    final repository = ref.watch(animalRepositoryProvider);

    await repository.getAll();
    final movements = await repository.getMovements();
    return AnimalState(
      animals: await repository.getLocal(),
      movements: movements,
    );
  }

  Future<void> save(Animal animal) async {
    try {
      await ref.read(animalRepositoryProvider).save(animal);
    } finally {
      if (ref.mounted) await reloadLocal();
    }
    if (!ref.mounted) return;

    unawaited(_requestSync());
  }

  Future<int> move(
    Animal animal,
    String destinationId,
    DateTime date, {
    int? plannedGrazingDays,
  }) async {
    return moveMany(
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
    final results = <({Animal animal, Movement movement})>[];
    var updatedPaddocks = <Paddock>[];
    await ref.read(databaseProvider).runInTransaction(() async {
      final currentAnimals = await ref
          .read(animalRepositoryProvider)
          .getLocal();
      final ids = selectedAnimals.map((a) => a.id).toSet();
      final movableAnimals = currentAnimals
          .where(
            (animal) =>
                ids.contains(animal.id) && animal.paddockId != destinationId,
          )
          .toList();
      if (movableAnimals.isEmpty) return;
      final paddocks = ref.read(paddockViewModelProvider).requireValue;
      final destination = paddocks.firstWhere(
        (paddock) => paddock.id == destinationId,
      );
      if (!PaddockOperationalStatus.calculate(
        destination,
        referenceDate: date,
      ).canReceiveAnimals) {
        throw StateError(
          'El potrero destino todavía no puede recibir animales.',
        );
      }
      final destinationWasEmpty = !currentAnimals.any(
        (animal) => animal.paddockId == destinationId,
      );
      if (destinationWasEmpty && plannedGrazingDays == null) {
        throw const FormatException(
          'Indica los días de uso planeado para el potrero destino.',
        );
      }

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
      updatedPaddocks = <Paddock>[
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

      for (final animal in movableAnimals) {
        results.add(await moveAnimal(animal, destinationId, date));
      }
      final paddockRepository = ref.read(paddockRepositoryProvider);
      for (final paddock in updatedPaddocks) {
        await paddockRepository.save(paddock);
      }
    });

    if (results.isEmpty) {
      await reloadLocal();
      return 0;
    }
    await reloadLocal();
    if (!ref.mounted) return results.length;
    final movements = await ref
        .read(animalLocalDataSourceProvider)
        .getMovements();
    if (!ref.mounted) return results.length;
    state = AsyncData(state.requireValue.copyWith(movements: movements));
    ref
        .read(paddockViewModelProvider.notifier)
        .applyPersistedMovementUpdates(updatedPaddocks);

    unawaited(_requestSync());

    return results.length;
  }

  Future<void> refreshFromRemote() async {
    try {
      await ref.read(animalRepositoryProvider).refreshAnimals();
    } finally {
      // A tombstone pull may have succeeded before the active GET failed.
      if (ref.mounted) await reloadLocal();
    }
  }

  Future<void> reload() async {
    final repository = ref.read(animalRepositoryProvider);
    await repository.getAll();
    final movements = await repository.getMovements();
    if (!ref.mounted) return;
    state = AsyncData(
      (state.value ?? const AnimalState()).copyWith(movements: movements),
    );
    await reloadLocal();
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
