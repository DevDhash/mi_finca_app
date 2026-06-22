import 'package:mi_finca_app/features/sync/data/datasources/mock_sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/domain/repositories/sync_repository.dart';

class SyncRepositoryImpl implements SyncRepository {
  const SyncRepositoryImpl(this._local, this._remote);
  final SyncLocalDataSource _local;
  final MockSyncRemoteDataSource _remote;
  @override
  Stream<void> get changes => _local.changes;
  @override
  Future<int> pendingCount() => _local.pendingCount();
  @override
  Future<DateTime?> lastSync() => _local.lastSync();
  @override
  Future<void> pushPendingChanges() async {
    await _remote.pushPendingChanges();
    await _local.markAllSynced();
  }
}
