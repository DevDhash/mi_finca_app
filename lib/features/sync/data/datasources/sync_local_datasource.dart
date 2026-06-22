import 'package:mi_finca_app/core/database/app_database.dart';

class SyncLocalDataSource {
  const SyncLocalDataSource(this._database);
  final AppDatabase _database;
  Stream<void> get changes => _database.recordChanges;
  Future<int> pendingCount() => _database.pendingCount();
  Future<DateTime?> lastSync() async {
    final raw = await _database.readSetting('last_sync');
    return raw == null ? null : DateTime.parse(raw);
  }

  Future<void> markAllSynced() async {
    await _database.markAllSynced();
    await _database.writeSetting('last_sync', DateTime.now().toIso8601String());
  }
}
