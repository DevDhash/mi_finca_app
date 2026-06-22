import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/domain/repositories/animal_repository.dart';

class AnimalRepositoryImpl implements AnimalRepository {
  const AnimalRepositoryImpl(this._local);
  final AnimalLocalDataSource _local;
  @override
  Future<List<Animal>> getAll() => _local.getAll();
  @override
  Future<List<Movement>> getMovements() => _local.getMovements();
  @override
  Future<void> save(Animal animal) => _local.save(animal);
  @override
  Future<void> saveMovement(Movement movement) => _local.saveMovement(movement);
}
