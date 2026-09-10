import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/domain/repositories/sync_repository.dart';

class SyncRepositoryImpl implements SyncRepository {
  const SyncRepositoryImpl(this._local, this._remote);

  final SyncLocalDataSource _local;
  final SyncRemoteDataSource _remote;

  @override
  Stream<void> get changes => _local.changes;

  @override
  Future<int> pendingCount() => _local.pendingCount();

  @override
  Future<DateTime?> lastSync() => _local.lastSync();

  @override
  Future<void> pushPendingChanges() async {
    final records = await _local.readPendingRecords();

    var syncedCount = 0;

    for (final record in records) {
      try {
        await _remote.pushRecord(record);

        await _local.markRecordSynced(
          collection: record.collection,
          id: record.id,
        );

        syncedCount++;
      } catch (_) {
        // Offline-first:
        // Si un registro falla, se mantiene pending = 1 para reintentar luego.
      }
    }

    if (syncedCount > 0) {
      await _local.saveLastSync(DateTime.now());
    }
  }
}
