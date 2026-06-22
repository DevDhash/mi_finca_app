import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/sync/data/datasources/mock_sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';
import 'package:mi_finca_app/features/sync/domain/repositories/sync_repository.dart';

class SyncState {
  const SyncState({
    this.pendingChanges = 0,
    this.lastSync,
    this.isOnline = true,
    this.isSyncing = false,
  });
  final int pendingChanges;
  final DateTime? lastSync;
  final bool isOnline;
  final bool isSyncing;
  SyncState copyWith({
    int? pendingChanges,
    DateTime? lastSync,
    bool? isOnline,
    bool? isSyncing,
  }) => SyncState(
    pendingChanges: pendingChanges ?? this.pendingChanges,
    lastSync: lastSync ?? this.lastSync,
    isOnline: isOnline ?? this.isOnline,
    isSyncing: isSyncing ?? this.isSyncing,
  );
}

final syncLocalDataSourceProvider = Provider(
  (ref) => SyncLocalDataSource(ref.watch(databaseProvider)),
);
final syncRemoteDataSourceProvider = Provider(
  (ref) => const MockSyncRemoteDataSource(),
);
final syncRepositoryProvider = Provider<SyncRepository>(
  (ref) => SyncRepositoryImpl(
    ref.watch(syncLocalDataSourceProvider),
    ref.watch(syncRemoteDataSourceProvider),
  ),
);
final syncViewModelProvider = AsyncNotifierProvider<SyncViewModel, SyncState>(
  SyncViewModel.new,
);

class SyncViewModel extends AsyncNotifier<SyncState> {
  StreamSubscription<void>? _subscription;
  @override
  Future<SyncState> build() async {
    final repo = ref.watch(syncRepositoryProvider);
    _subscription = repo.changes.listen((_) => refreshPending());
    ref.onDispose(() => _subscription?.cancel());
    return SyncState(
      pendingChanges: await repo.pendingCount(),
      lastSync: await repo.lastSync(),
    );
  }

  Future<void> refreshPending() async {
    final value = state.value;
    if (value == null) return;
    state = AsyncData(
      value.copyWith(
        pendingChanges: await ref.read(syncRepositoryProvider).pendingCount(),
      ),
    );
  }

  void setOnline(bool online) {
    final value = state.value;
    if (value != null) state = AsyncData(value.copyWith(isOnline: online));
  }

  Future<void> syncNow() async {
    final value = state.requireValue;
    if (!value.isOnline || value.pendingChanges == 0) return;
    state = AsyncData(value.copyWith(isSyncing: true));
    await ref.read(syncRepositoryProvider).pushPendingChanges();
    state = AsyncData(
      state.requireValue.copyWith(
        isSyncing: false,
        pendingChanges: 0,
        lastSync: DateTime.now(),
      ),
    );
  }
}
