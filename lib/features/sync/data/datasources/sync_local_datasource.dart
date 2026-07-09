import 'package:mi_finca_app/core/database/app_database.dart';

class SyncLocalDataSource {
  const SyncLocalDataSource(this._database);

  final AppDatabase _database;

  Stream<void> get changes => _database.recordChanges;

  Future<int> pendingCount() => _database.pendingCount();

  Future<List<PendingRecord>> readPendingRecords() {
    return _database.readPendingRecords();
  }

  Future<void> markRecordSynced({
    required String collection,
    required String id,
  }) {
    return _database.markRecordSynced(collection, id);
  }

  Future<DateTime?> lastSync() async {
    final raw = await _database.readSetting('last_sync');
    return raw == null ? null : DateTime.parse(raw);
  }

  Future<void> saveLastSync(DateTime value) {
    return _database.writeSetting('last_sync', value.toIso8601String());
  }

  Future<void> markAllSynced() async {
    await _database.markAllSynced();
    await saveLastSync(DateTime.now());
  }
}
