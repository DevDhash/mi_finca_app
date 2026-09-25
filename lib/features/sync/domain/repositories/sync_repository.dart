abstract interface class SyncRepository {
  Stream<void> get changes;
  Future<int> pendingCount();
  Future<DateTime?> lastSync();
  Future<void> pushPendingChanges();
}

/// Explicit pull, including when there are no pending writes.
abstract interface class TombstoneSyncRepository implements SyncRepository {
  Future<void> pullRemoteTombstones();
  Future<void> markDeleted(String collection, String id, String ownerId);
  Future<bool> verifyLegacyOwnership(
    String collection,
    String id,
    String ownerId,
  );
}
