import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_model.dart';
import 'package:mi_finca_app/features/animals/data/models/movement_model.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';

class AnimalLocalDataSource {
  const AnimalLocalDataSource(this._database);
  final AppDatabase _database;
  Future<List<Animal>> getAll() async => (await _database.readRecords(
    'animals',
  )).map(AnimalModel.fromJson).toList();
  Future<List<Movement>> getMovements() async => (await _database.readRecords(
    'movements',
  )).map(MovementModel.fromJson).toList();
  Future<void> save(Animal animal) => _database.putRecord(
    'animals',
    animal.id,
    AnimalModel.toJson(animal),
    animal.updatedAt,
  );
  Future<void> saveMovement(Movement movement) => _database.putRecord(
    'movements',
    movement.id,
    MovementModel.toJson(movement),
    movement.date,
  );
}
