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

    if (localItems.isNotEmpty) return localItems;

    try {
      return await refreshAnimals();
    } catch (_) {
      return _local.getAll();
    }
  }

  @override
  Future<List<Animal>> refreshAnimals() async {
    final owner = _remote.currentUserId;
    if (owner == null) {
      throw StateError('Inicia sesión para actualizar animales.');
    }
    final snapshot = await _local.snapshotForRefresh(owner);
    final remoteItems = await _remote.getAnimals();
    if (_remote.currentUserId != owner) {
      throw StateError('La sesión cambió durante la actualización.');
    }
    await _local.mergeRemoteAnimals(remoteItems, snapshot);
    return _local.getAll();
  }

  @override
  Future<List<Movement>> getMovements() async {
    final localItems = await _local.getMovements();

    if (localItems.isNotEmpty) return localItems;

    try {
      final remoteItems = await _remote.getMovements();

      for (final movement in remoteItems) {
        await _local.saveMovement(movement, pending: false);
      }

      return remoteItems;
    } catch (_) {
      return localItems;
    }
  }

  @override
  Future<void> save(Animal animal) async {
    await _local.save(animal);
  }

  @override
  Future<void> saveMovement(Movement movement) async {
    await _local.saveMovement(movement);
  }
}
