import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/paddocks/data/models/paddock_model.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';

class PaddockLocalDataSource {
  const PaddockLocalDataSource(this._database);
  final AppDatabase _database;
  Future<List<Paddock>> getAll() async => (await _database.readRecords(
    'paddocks',
  )).map(PaddockModel.fromJson).toList();
  Future<void> save(Paddock paddock) => _database.putRecord(
    'paddocks',
    paddock.id,
    PaddockModel.toJson(paddock),
    paddock.updatedAt,
  );
}
