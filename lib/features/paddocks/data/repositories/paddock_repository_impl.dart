import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_history_reference.dart';
import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_patch.dart';
import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_local_datasource.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_remote_datasource.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/repositories/paddock_repository.dart';

class PaddockRepositoryImpl
    implements
        PaddockRepository,
        PaddockEditRepository,
        PaddockHistoryRepository,
        PaddockRefreshRepository {
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
  Future<List<Paddock>> getLocal() => _local.getAll();

  @override
  Future<List<Paddock>> refreshPaddocks() async {
    final generation = _local.sessionGeneration;
    final owner = _remote.currentUserId;
    if (owner == null) throw StateError('Sesión requerida');
    final snapshot = await _local.snapshot(owner);
    final items = await _remote.getAll();
    if (_local.sessionGeneration != generation ||
        _remote.currentUserId != owner) {
      throw StateError('La sesión cambió');
    }
    await _local.mergeRemote(items, owner, snapshot);
    return _local.getAll();
  }

  @override
  Future<Map<String, PaddockHistoryReference>> resolveHistory(
    Set<String> ids,
  ) => _local.resolveHistory(ids);

  @override
  Future<void> edit(String id, PaddockPatch patch) => _local.edit(id, patch);

  @override
  Future<void> save(Paddock paddock) async {
    await _local.save(paddock);
  }
}
