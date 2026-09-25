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

    if (localItems.isNotEmpty) return localItems;

    try {
      final owner = _remote.currentUserId;
      final remoteItems = await _remote.getAll();

      if (_remote.currentUserId != owner) throw StateError('La sesión cambió.');
      for (final paddock in remoteItems) {
        await _local.save(
          paddock.copyWith(syncStatus: SyncStatus.synced),
          pending: false,
          verifiedRemoteOwner: owner,
        );
      }

      return _local.getAll();
    } catch (_) {
      return localItems;
    }
  }

  @override
  Future<void> save(Paddock paddock) async {
    await _local.save(paddock);
  }
}
