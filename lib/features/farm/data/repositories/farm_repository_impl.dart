import 'package:mi_finca_app/features/farm/data/datasources/farm_local_datasource.dart';
import 'package:mi_finca_app/features/farm/data/datasources/farm_remote_datasource.dart';
import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';
import 'package:mi_finca_app/features/farm/domain/repositories/farm_repository.dart';

class FarmRepositoryImpl implements FarmRepository {
  const FarmRepositoryImpl({
    required FarmLocalDataSource local,
    required FarmRemoteDataSource remote,
  }) : _local = local,
       _remote = remote;

  final FarmLocalDataSource _local;
  final FarmRemoteDataSource _remote;

  @override
  Future<Farm?> getFarm() async {
    final localFarm = await _local.read();

    if (localFarm != null) {
      return localFarm;
    }

    try {
      final remoteFarm = await _remote.readCurrentUserFarm();

      if (remoteFarm != null) {
        await _local.write(remoteFarm, pending: false);
      }

      return remoteFarm;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveFarm(Farm farm) async {
    await _local.write(farm);
  }
}
