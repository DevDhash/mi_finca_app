import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/animals/domain/repositories/animal_repository.dart';
import 'package:uuid/uuid.dart';

class MoveAnimal {
  const MoveAnimal(this._repository);
  final AnimalRepository _repository;

  Future<({Animal animal, Movement movement})> call(
    Animal animal,
    String destinationId,
    DateTime date,
  ) async {
    final movement = Movement(
      id: const Uuid().v4(),
      animalId: animal.id,
      fromPaddockId: animal.paddockId,
      toPaddockId: destinationId,
      date: date,
    );
    final moved = animal.copyWith(
      paddockId: destinationId,
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
    );
    await _repository.saveMovement(movement);
    await _repository.save(moved);
    return (animal: moved, movement: movement);
  }
}
