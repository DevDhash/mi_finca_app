import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_remote_datasource.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/animals/domain/repositories/animal_repository.dart';

class AnimalRepositoryImpl implements AnimalRepository {
  const AnimalRepositoryImpl({
    required AnimalLocalDataSource local,
    required AnimalRemoteDataSource remote,
    Future<void> Function()? pullTombstones,
  }) : _local = local,
       _remote = remote,
       _pullTombstones = pullTombstones;

  final AnimalLocalDataSource _local;
  final AnimalRemoteDataSource _remote;
  final Future<void> Function()? _pullTombstones;

  @override
  Future<List<Animal>> getAll() async {
    final localItems = await _local.getAll();

    if (localItems.isNotEmpty || await _local.hasStoredAnimals()) {
      return localItems;
    }

    try {
      return await refreshAnimals();
    } catch (_) {
      return _local.getAll();
    }
  }

  @override
  Future<List<Animal>> getLocal() => _local.getAll();

  @override
  Future<AnimalDeletionResult> deleteAnimal(String id) async {
    final owner = await _local.owner();
    bool sessionMatches() =>
        _remote.currentUserId == null || _remote.currentUserId == owner;
    if (owner == null || !sessionMatches()) {
      return AnimalDeletionResult.ownershipFailure;
    }
    final record = await _local.record(id);
    if (record == null) return AnimalDeletionResult.notFound;
    final photoOwner = (record.payload['_photoUpload'] as Map?)?['ownerId'];
    if ((record.ownerId != null && record.ownerId != owner) ||
        (photoOwner != null && photoOwner != owner)) {
      return AnimalDeletionResult.ownershipFailure;
    }
    AnimalDeletionResult translate(AnimalLocalDeletion result) =>
        switch (result) {
          AnimalLocalDeletion.accepted => AnimalDeletionResult.accepted,
          AnimalLocalDeletion.alreadyDeleted =>
            AnimalDeletionResult.alreadyDeleted,
          AnimalLocalDeletion.notFound => AnimalDeletionResult.notFound,
          AnimalLocalDeletion.needsVerification =>
            AnimalDeletionResult.needsVerification,
        };
    Future<AnimalDeletionResult> acceptLocal() async {
      try {
        if (!sessionMatches()) return AnimalDeletionResult.ownershipFailure;
        return translate(await _local.deleteAnimal(id, owner));
      } catch (_) {
        if (!sessionMatches() || await _local.owner() != owner) {
          return AnimalDeletionResult.ownershipFailure;
        }
        rethrow; // Disk/transaction failures are unexpected, not verification outcomes.
      }
    }

    final result = await acceptLocal();
    if (result != AnimalDeletionResult.needsVerification) return result;
    if (_remote.currentUserId != owner) {
      return AnimalDeletionResult.needsVerification;
    }
    final bool exists;
    try {
      // An empty result or network/RLS error cannot establish LOCAL_ONLY.
      exists = await _remote.verifyAnimalOwner(id, owner);
    } catch (_) {
      if (_remote.currentUserId != owner || await _local.owner() != owner) {
        return AnimalDeletionResult.ownershipFailure;
      }
      return AnimalDeletionResult.needsVerification;
    }
    if (_remote.currentUserId != owner || await _local.owner() != owner) {
      return AnimalDeletionResult.ownershipFailure;
    }
    if (!exists) return AnimalDeletionResult.needsVerification;
    try {
      await _local.confirm(id, owner);
    } catch (_) {
      if (_remote.currentUserId != owner || await _local.owner() != owner) {
        return AnimalDeletionResult.ownershipFailure;
      }
      rethrow;
    }
    if (_remote.currentUserId != owner) {
      return AnimalDeletionResult.ownershipFailure;
    }
    return acceptLocal();
  }

  @override
  Future<List<Animal>> refreshAnimals() async {
    final owner = _remote.currentUserId;
    if (owner == null) {
      throw StateError('Inicia sesión para actualizar animales.');
    }
    await _pullTombstones?.call();
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

    if (localItems.isNotEmpty || await _local.hasStoredMovements()) {
      return localItems;
    }

    try {
      final owner = _remote.currentUserId;
      final remoteItems = await _remote.getMovements();
      if (_remote.currentUserId != owner) throw StateError('La sesión cambió.');

      for (final movement in remoteItems) {
        await _local.saveMovement(
          movement,
          pending: false,
          verifiedRemoteOwner: owner,
        );
      }

      return _local.getMovements();
    } catch (_) {
      return localItems;
    }
  }

  @override
  Future<void> save(Animal animal) async {
    await _local.save(animal);
  }

  @override
  Future<void> saveMove(Animal animal, Movement movement) =>
      _local.saveMove(animal, movement);

  @override
  Future<void> saveMovement(Movement movement) async {
    await _local.saveMovement(movement);
  }
}
