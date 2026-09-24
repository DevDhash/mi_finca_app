import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/sync/domain/repositories/sync_repository.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';

void main() {
  late FakeSyncRepository repository;
  late ProviderContainer container;
  setUp(() {
    repository = FakeSyncRepository();
    container = ProviderContainer(
      overrides: [syncRepositoryProvider.overrideWithValue(repository)],
    );
  });
  tearDown(() => container.dispose());

  test(
    'first save waits for notifier initialization instead of skipping sync',
    () async {
      final notifier = container.read(syncViewModelProvider.notifier);
      await notifier.syncPendingIfOnline();
      expect(repository.calls, 1);
      expect(
        container.read(syncViewModelProvider).requireValue.isSyncing,
        isFalse,
      );
    },
  );

  test('manual offline mode does not start uploads', () async {
    await container.read(syncViewModelProvider.future);
    final notifier = container.read(syncViewModelProvider.notifier);
    notifier.setOnline(false);
    await notifier.syncPendingIfOnline();
    expect(repository.calls, 0);
  });

  test('manual and save sync cannot run in parallel', () async {
    await container.read(syncViewModelProvider.future);
    final notifier = container.read(syncViewModelProvider.notifier);
    repository.gate = Completer<void>();
    final active = notifier.syncNow();
    await notifier.syncNow();
    await notifier.syncPendingIfOnline();
    expect(repository.calls, 1);
    repository.gate!.complete();
    await active;
  });

  test('syncing indicator is reset if the worker throws', () async {
    await container.read(syncViewModelProvider.future);
    repository.fail = true;
    await expectLater(
      container.read(syncViewModelProvider.notifier).syncNow(),
      throwsStateError,
    );
    expect(
      container.read(syncViewModelProvider).requireValue.isSyncing,
      isFalse,
    );
  });
}

class FakeSyncRepository implements SyncRepository {
  int calls = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<DateTime?> lastSync() async => null;
  @override
  Future<int> pendingCount() async => 1;
  @override
  Future<void> pushPendingChanges() async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('failed');
  }
}
