import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';
import 'package:mi_finca_app/features/farm/data/datasources/farm_local_datasource.dart';
import 'package:mi_finca_app/features/farm/domain/repositories/farm_repository.dart';

class FarmRepositoryImpl implements FarmRepository {
  const FarmRepositoryImpl(this._local);
  final FarmLocalDataSource _local;
  @override
  Future<Farm?> getFarm() => _local.read();
  @override
  Future<void> saveFarm(Farm farm) => _local.write(farm);
}
