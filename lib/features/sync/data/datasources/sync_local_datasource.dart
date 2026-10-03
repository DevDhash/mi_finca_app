import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';

class SyncLocalDataSource {
  const SyncLocalDataSource(this._database);

  final AppDatabase _database;

  Future<PendingRecord?> beginRemotePublish(PendingRecord record) =>
      _database.beginRemotePublish(record);

  Future<void> markRemoteConfirmed(
    String collection,
    String id,
    String owner,
  ) => _database.markRemoteConfirmed(collection, id, owner);

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

  Future<List<PendingRecord>> rejectedPaddockDeletes(String owner) async {
    await _database.requireOwner(owner);
    final rows = <PendingRecord>[];
    for (final payload in await _database.readRecords(
      'paddocks',
      includeDeleted: true,
    )) {
      if (SyncMetadata.owner(payload) == owner &&
          SyncMetadata.deletionState(payload) == DeletionState.conflict &&
          SyncMetadata.read(payload)['deleteRejection'] ==
              'SYNC_PADDOCK_OCCUPIED') {
        rows.add(
          (await _database.readRecord(
            'paddocks',
            payload['id']! as String,
            includeDeleted: true,
          ))!,
        );
      }
    }
    return rows;
  }

  Future<bool> reconcilePaddockDelete(
    PendingRecord record,
    Map<String, Object?> active,
  ) => _database.reconcileRejectedPaddockDelete(
    record,
    remoteOwner: record.ownerId!,
    activePayload: active,
  );

  Future<bool> rejectPaddockDelete(PendingRecord record, String code) =>
      _database.rejectPaddockDelete(record, code);

  // ---------------------------------------------------------------------------
  // PADDOCK PATCHES
  // ---------------------------------------------------------------------------

  Future<bool> patchReady(PendingRecord record) => _database.patchReady(record);

  Future<List<PendingRecord>> patches(String owner) =>
      _database.paddockPatches(owner);

  Future<bool> finishPatch(PendingRecord record, {String? error}) =>
      _database.finishPaddockPatch(record, error: error);

  Future<bool> bindPatchVersion(PendingRecord record, String version) =>
      _database.replaceRecordIfUnchanged(record, {
        ...record.payload,
        'remoteBaseVersion': version,
      }, pending: true);

  // ---------------------------------------------------------------------------
  // ANIMAL PATCHES
  // ---------------------------------------------------------------------------

  Future<bool> quarantineAnimal(PendingRecord record) =>
      _database.quarantineLegacyAnimal(record);

  Future<List<PendingRecord>> animalPatches(String owner) =>
      _database.animalPatches(owner);

  Future<bool> animalPatchReady(PendingRecord record) =>
      _database.animalPatchReady(record);

  Future<bool> finishAnimalPatch(PendingRecord record, {String? error}) =>
      _database.finishAnimalPatch(record, error: error);

  // ---------------------------------------------------------------------------
  // ATOMIC ANIMAL MOVES
  // ---------------------------------------------------------------------------

  /// Returns all durable MOVE commands belonging to [owner].
  ///
  /// This includes pending/completed/conflict commands. The caller decides
  /// which lifecycle states are eligible for publication.
  Future<List<PendingRecord>> animalMoves(String owner) =>
      _database.animalMoveCommands(owner);

  /// Reconciles the optimistic local MOVE projection with the authoritative
  /// state returned after sync_move_animal() succeeds.
  ///
  /// This does NOT complete the command. Completion happens separately only
  /// after reconciliation succeeds.
  Future<bool> reconcileAnimalMoveSuccess(
    PendingRecord record, {
    required Map<String, Object?> movement,
    required Map<String, Object?> state,
  }) => _database.reconcileAnimalMoveSuccess(
    record,
    movement: movement,
    state: state,
  );

  /// Marks the durable MOVE command as completed.
  ///
  /// Must only be called after successful authoritative reconciliation.
  Future<bool> reconcileRejectedAnimalMove(
    PendingRecord record,
    Map<String, Object?> state,
  ) => _database.reconcileRejectedAnimalMove(record, state);

  Future<bool> completeAnimalMove(PendingRecord record) =>
      _database.completeAnimalMoveCommand(record);

  /// Converts a positively identified business rejection into a durable local
  /// conflict. Transient/unknown delivery failures must NOT call this method.
  Future<bool> conflictAnimalMove(PendingRecord record, String error) =>
      _database.conflictAnimalMoveCommand(record, error);

  // ---------------------------------------------------------------------------
  // GENERIC SYNC
  // ---------------------------------------------------------------------------

  Stream<void> get changes => _database.recordChanges;

  Future<int> pendingCount() => _database.pendingCount();

  Future<List<PendingRecord>> readPendingRecords() =>
      _database.readPendingRecords();

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
