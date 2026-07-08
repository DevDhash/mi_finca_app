import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_local_datasource.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_remote_datasource.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/repositories/paddock_repository.dart';

class PaddockRepositoryImpl implements PaddockRepository {
  const PaddockRepositoryImpl({
    required PaddockLocalDataSource local,
    required PaddockRemoteDataSource remote,
  }) : _local = local,
       _remote = remote;

  final PaddockLocalDataSource _local;
  final PaddockRemoteDataSource _remote;

  @override
  Future<List<Paddock>> getAll() async {
    final localItems = await _local.getAll();

    if (localItems.isNotEmpty) {
      for (final paddock in localItems) {
        try {
          await _remote.upsert(paddock);
        } catch (_) {
          // Offline-first:
          // Si falla Supabase, seguimos usando la data local.
        }
      }

      return localItems;
    }

    try {
      final remoteItems = await _remote.getAll();

      for (final paddock in remoteItems) {
        await _local.save(paddock);
      }

      return remoteItems;
    } catch (_) {
      return localItems;
    }
  }

  @override
  Future<void> save(Paddock paddock) async {
    await _local.save(paddock);

    try {
      await _remote.upsert(paddock.copyWith(syncStatus: SyncStatus.synced));
    } catch (_) {
      // Offline-first:
      // Si Supabase falla, queda guardado localmente como pendiente.
    }
  }
}
