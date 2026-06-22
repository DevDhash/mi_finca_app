class MockSyncRemoteDataSource {
  const MockSyncRemoteDataSource();
  Future<void> pushPendingChanges() =>
      Future<void>.delayed(const Duration(milliseconds: 900));
}
