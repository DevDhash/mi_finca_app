import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';

class SyncLocalDataSource {
  const SyncLocalDataSource(this._database);

  final AppDatabase _database;

  Future<PendingRecord?> find(String collection, String id) =>
      _database.readRecord(collection, id, includeDeleted: true);
  Future<String?> localOwner() => _database.localOwner();
  Future<void> requireOwner(String owner) => _database.requireOwner(owner);
  Future<bool> adoptVerifiedOwner(PendingRecord record, String owner) =>
      _database.adoptVerifiedOwner(record, owner);
  Future<PendingRecord?> current(PendingRecord record) =>
      _database.readRecord(record.collection, record.id, includeDeleted: true);
  Future<void> markDeleted(String collection, String id, String owner) =>
      _database.markDeleted(collection, id, owner);
  Future<bool> acknowledgeDelete(
    PendingRecord record,
    RemoteTombstone remote,
  ) => _database.acknowledgeDelete(record, remote);
  Future<void> mergeTombstones(String owner, List<RemoteTombstone> records) =>
      _database.mergeRemoteTombstones(owner, records);

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

  Future<bool> acknowledge(PendingRecord record) => _database
      .replaceRecordIfUnchanged(record, record.payload, pending: false);

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
