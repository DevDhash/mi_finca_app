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
      try {
        await _remote.upsertFarm(localFarm);
      } catch (_) {
        // Offline-first:

        // Si Supabase falla, usamos la finca local sin romper la app.
      }

      return localFarm;
    }

    try {
      final remoteFarm = await _remote.readCurrentUserFarm();

      if (remoteFarm != null) {
        await _local.write(remoteFarm);
      }

      return remoteFarm;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveFarm(Farm farm) async {
    await _local.write(farm);

    try {
      await _remote.upsertFarm(farm);
    } catch (_) {
      // Offline-first:
      // Si Supabase falla, mantenemos la finca guardada localmente.
      // Luego conectaremos esto con el módulo de sync/outbox.
    }
  }
}
