import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';

abstract interface class AnimalRepository {
  Future<List<Animal>> getAll();
  Future<List<Animal>> getLocal();
  Future<AnimalDeletionResult> deleteAnimal(String id);
  Future<List<Animal>> refreshAnimals();
  Future<List<Movement>> getMovements();
  Future<void> save(Animal animal);
  Future<void> saveMovement(Movement movement);
  Future<void> saveMove(Animal animal, Movement movement);
}

enum AnimalDeletionResult {
  accepted,
  needsVerification,
  ownershipFailure,
  notFound,
  alreadyDeleted,
}
