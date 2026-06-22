abstract interface class SyncRepository {
  Stream<void> get changes;
  Future<int> pendingCount();
  Future<DateTime?> lastSync();
  Future<void> pushPendingChanges();
}
