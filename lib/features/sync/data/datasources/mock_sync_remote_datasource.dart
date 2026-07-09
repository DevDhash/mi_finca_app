import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';

class MockSyncRemoteDataSource implements SyncRemoteDataSource {
  const MockSyncRemoteDataSource();

  @override
  Future<void> pushRecord(PendingRecord record) {
    return Future<void>.delayed(const Duration(milliseconds: 150));
  }
}
