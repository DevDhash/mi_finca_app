import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_remote_datasource.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/animals/domain/repositories/animal_repository.dart';

class AnimalRepositoryImpl implements AnimalRepository {
  const AnimalRepositoryImpl({
    required AnimalLocalDataSource local,
    required AnimalRemoteDataSource remote,
  }) : _local = local,
       _remote = remote;

  final AnimalLocalDataSource _local;
  final AnimalRemoteDataSource _remote;

  @override
  Future<List<Animal>> getAll() async {
    final localItems = await _local.getAll();

    if (localItems.isNotEmpty) {
      for (final animal in localItems) {
        try {
          await _remote.upsertAnimal(animal);
        } catch (_) {
          // Offline-first:
          // Si falla Supabase, seguimos usando la data local.
        }
      }

      return localItems;
    }

    try {
      final remoteItems = await _remote.getAnimals();

      for (final animal in remoteItems) {
        await _local.save(animal);
      }

      return remoteItems;
    } catch (_) {
      return localItems;
    }
  }

  @override
  Future<List<Movement>> getMovements() async {
    final localItems = await _local.getMovements();

    if (localItems.isNotEmpty) {
      for (final movement in localItems) {
        try {
          await _remote.upsertMovement(movement);
        } catch (_) {
          // Offline-first:
          // Si falla Supabase, seguimos usando movimientos locales.
        }
      }

      return localItems;
    }

    try {
      final remoteItems = await _remote.getMovements();

      for (final movement in remoteItems) {
        await _local.saveMovement(movement);
      }

      return remoteItems;
    } catch (_) {
      return localItems;
    }
  }

  @override
  Future<void> save(Animal animal) async {
    await _local.save(animal);

    try {
      await _remote.upsertAnimal(
        animal.copyWith(syncStatus: SyncStatus.synced),
      );
    } catch (_) {
      // Offline-first:
      // Si falla Supabase, queda guardado localmente como pendiente.
    }
  }

  @override
  Future<void> saveMovement(Movement movement) async {
    await _local.saveMovement(movement);

    try {
      await _remote.upsertMovement(movement);
    } catch (_) {
      // Offline-first:
      // Si falla Supabase, queda guardado localmente.
    }
  }
}
