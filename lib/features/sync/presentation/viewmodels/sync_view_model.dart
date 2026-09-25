import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/farm/presentation/viewmodels/farm_view_model.dart';
import 'dart:async';

import 'package:mi_finca_app/core/network/network_status.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_photo_storage.dart';
import 'package:mi_finca_app/features/animals/data/services/animal_photo_sync.dart';
import 'package:mi_finca_app/features/sync/data/datasources/supabase_sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';
import 'package:mi_finca_app/features/sync/domain/repositories/sync_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SyncState {
  const SyncState({
    this.pendingChanges = 0,
    this.lastSync,
    this.isOnline = true,
    this.manualOffline = false,
    this.isSyncing = false,
  });

  final int pendingChanges;
  final DateTime? lastSync;
  final bool isOnline;
  final bool manualOffline;
  final bool isSyncing;

  SyncState copyWith({
    int? pendingChanges,
    DateTime? lastSync,
    bool? isOnline,
    bool? manualOffline,
    bool? isSyncing,
  }) => SyncState(
    pendingChanges: pendingChanges ?? this.pendingChanges,
    lastSync: lastSync ?? this.lastSync,
    isOnline: isOnline ?? this.isOnline,
    manualOffline: manualOffline ?? this.manualOffline,
    isSyncing: isSyncing ?? this.isSyncing,
  );
}

final syncLocalDataSourceProvider = Provider(
  (ref) => SyncLocalDataSource(ref.watch(databaseProvider)),
);

final syncRemoteDataSourceProvider = Provider<SyncRemoteDataSource>(
  (ref) => SupabaseSyncRemoteDataSource(Supabase.instance.client),
);

final syncRepositoryProvider = Provider<SyncRepository>(
  (ref) => SyncRepositoryImpl(
    ref.watch(syncLocalDataSourceProvider),
    ref.watch(syncRemoteDataSourceProvider),
    photos: AnimalPhotoSync(
      ref.watch(databaseProvider),
      SupabaseAnimalPhotoStorage(Supabase.instance.client),
    ),
  ),
);

final syncViewModelProvider = AsyncNotifierProvider<SyncViewModel, SyncState>(
  SyncViewModel.new,
);

class SyncViewModel extends AsyncNotifier<SyncState> {
  StreamSubscription<void>? _subscription;
  bool _networkOnline = true;

  @override
  Future<SyncState> build() async {
    final repo = ref.watch(syncRepositoryProvider);

    _subscription = repo.changes.listen((_) => refreshPending());
    ref.onDispose(() => _subscription?.cancel());

    return SyncState(
      manualOffline: ref.read(manualOfflineProvider),
      isOnline: !ref.read(manualOfflineProvider),
      pendingChanges: await repo.pendingCount(),
      lastSync: await repo.lastSync(),
    );
  }

  Future<void> refreshPending() async {
    final value = state.value;
    if (value == null) return;

    final count = await ref.read(syncRepositoryProvider).pendingCount();
    if (!ref.mounted) return;
    state = AsyncData(state.requireValue.copyWith(pendingChanges: count));
  }

  void setOnline(bool online) {
    ref.read(manualOfflineProvider.notifier).set(!online);
    final value = state.value;
    if (value != null) {
      state = AsyncData(
        value.copyWith(
          isOnline: online && _networkOnline,
          manualOffline: !online,
        ),
      );
    }
  }

  void setConnectivity(bool online) {
    _networkOnline = online;
    final value = state.value;
    if (value != null) {
      state = AsyncData(
        value.copyWith(isOnline: online && !value.manualOffline),
      );
    }
  }

  Future<void> syncNow() async {
    await _syncPendingChanges(state.requireValue);
    if (!state.requireValue.isOnline) return;
    final repository = ref.read(syncRepositoryProvider);
    if (repository is TombstoneSyncRepository) {
      await repository.pullRemoteTombstones();
      if (!ref.mounted) return;
      ref.invalidate(animalViewModelProvider);
      ref.invalidate(expenseViewModelProvider);
      ref.invalidate(paddockViewModelProvider);
      ref.invalidate(farmViewModelProvider);
    }
  }

  Future<void> syncPendingIfOnline() async {
    // The first save can arrive before this notifier has finished building.
    final value = state.value ?? await future;
    if (!ref.mounted || value.isSyncing) return;

    final repository = ref.read(syncRepositoryProvider);
    final pendingChanges = await repository.pendingCount();

    if (!ref.mounted || state.value?.isSyncing == true) return;
    final refreshed = state.requireValue.copyWith(
      pendingChanges: pendingChanges,
    );
    state = AsyncData(refreshed);

    await _syncPendingChanges(refreshed);
  }

  Future<void> _syncPendingChanges(SyncState value) async {
    if (!value.isOnline ||
        value.pendingChanges == 0 ||
        state.value?.isSyncing == true) {
      return;
    }

    state = AsyncData(value.copyWith(isSyncing: true));

    final repository = ref.read(syncRepositoryProvider);
    try {
      await repository.pushPendingChanges();
    } finally {
      final pending = await repository.pendingCount();
      final lastSync = await repository.lastSync();
      if (ref.mounted) {
        state = AsyncData(
          state.requireValue.copyWith(
            isSyncing: false,
            pendingChanges: pending,
            lastSync: lastSync,
          ),
        );
        if (ref.exists(animalViewModelProvider)) {
          await ref.read(animalViewModelProvider.notifier).reloadLocal();
        }
      }
    }
  }
}
