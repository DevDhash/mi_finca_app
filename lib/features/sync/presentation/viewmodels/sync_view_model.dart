import 'package:mi_finca_app/features/farm/presentation/viewmodels/farm_view_model.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_local_datasource.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'dart:async';
import 'package:mi_finca_app/features/sync/data/services/manual_data_refresh.dart';

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
    this.isRefreshing = false,
    this.lastDataRefresh,
    this.refreshResult,
  });

  final DateTime? lastDataRefresh;
  final ManualRefreshResult? refreshResult;
  final int pendingChanges;
  final DateTime? lastSync;
  final bool isOnline;
  final bool manualOffline;
  final bool isSyncing;
  final bool isRefreshing;

  SyncState copyWith({
    DateTime? lastDataRefresh,
    ManualRefreshResult? refreshResult,
    int? pendingChanges,
    DateTime? lastSync,
    bool? isOnline,
    bool? manualOffline,
    bool? isSyncing,
    bool? isRefreshing,
  }) => SyncState(
    lastDataRefresh: lastDataRefresh ?? this.lastDataRefresh,
    refreshResult: refreshResult ?? this.refreshResult,
    pendingChanges: pendingChanges ?? this.pendingChanges,
    lastSync: lastSync ?? this.lastSync,
    isOnline: isOnline ?? this.isOnline,
    manualOffline: manualOffline ?? this.manualOffline,
    isSyncing: isSyncing ?? this.isSyncing,
    isRefreshing: isRefreshing ?? this.isRefreshing,
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

final manualDataRefreshFactoryProvider =
    Provider<Future<ManualDataRefresh> Function()>(
      (ref) => () async {
        final db = ref.read(databaseProvider);
        final owner = await db.localOwner();
        final generation = db.sessionGeneration;
        final repository = ref.read(syncRepositoryProvider);
        final animalLocal = ref.read(animalLocalDataSourceProvider);
        final paddockLocal = ref.read(paddockLocalDataSourceProvider);
        final expenseLocal = ref.read(expenseLocalDataSourceProvider);
        late AnimalRefreshSnapshot animalSnapshot;
        late ExpenseRefreshSnapshot expenseSnapshot;
        late Map<String, String> paddockSnapshot;
        late Map<String, String> movementSnapshot;
        late List<Animal> animals;
        late List<Paddock> paddocks;
        late List<Movement> movements;
        late List<Expense> expenses;
        Future<void> validate() async {
          if (!ref.mounted ||
              owner == null ||
              db.sessionGeneration != generation ||
              await db.localOwner() != owner ||
              ref.read(animalRemoteDataSourceProvider).currentUserId != owner) {
            throw StateError('La sesión cambió');
          }
          if (ref.read(manualOfflineProvider) ||
              !(ref.read(networkStatusProvider).asData?.value ?? false)) {
            throw StateError('Sin conexión');
          }
        }

        return ManualDataRefresh(
          validate: validate,
          push: repository.pushPendingChanges,
          tombstones: () async {
            if (repository is! TombstoneSyncRepository) {
              throw StateError('Eliminaciones no disponibles');
            }
            await (repository).pullRemoteTombstones();
          },
          snapshots: () async {
            await validate();
            animalSnapshot = await animalLocal.snapshotForRefresh(owner!);
            paddockSnapshot = await paddockLocal.snapshot(owner);
            movementSnapshot = await animalLocal.movementSnapshot(owner);
            expenseSnapshot = await expenseLocal.snapshot(owner);
          },
          downloads: {
            'potreros': () async {
              paddocks = await ref
                  .read(paddockRemoteDataSourceProvider)
                  .getAll();
            },
            'animales': () async {
              animals = await ref
                  .read(animalRemoteDataSourceProvider)
                  .getAnimals();
            },
            'movimientos': () async {
              movements = await ref
                  .read(animalRemoteDataSourceProvider)
                  .getMovements();
            },
            'gastos': () async {
              expenses = await ref
                  .read(expenseRemoteDataSourceProvider)
                  .getAll();
            },
          },
          merges: {
            'potreros': () => db.runInTransaction(() async {
              await validate();
              await paddockLocal.mergeRemote(paddocks, owner!, paddockSnapshot);
              await validate();
            }),
            'animales': () => db.runInTransaction(() async {
              await validate();
              await animalLocal.mergeRemoteAnimals(animals, animalSnapshot);
              await validate();
            }),
            'movimientos': () => db.runInTransaction(() async {
              await validate();
              await animalLocal.mergeRemoteMovements(
                movements,
                owner!,
                movementSnapshot,
              );
              await validate();
            }),
            'gastos': () => db.runInTransaction(() async {
              await validate();
              await expenseLocal.mergeActive(expenses, owner!, expenseSnapshot);
              await validate();
            }),
          },
          reload: () async {
            await validate();
            await ref.read(animalViewModelProvider.notifier).reloadAllLocal();
            await ref.read(paddockViewModelProvider.notifier).reloadLocal();
            await ref.read(expenseViewModelProvider.notifier).reload();
          },
          updatePending: () =>
              ref.read(syncViewModelProvider.notifier).refreshPending(),
          saveSuccess: () => db.runInTransaction(() async {
            await validate();
            await db.writeSetting(
              'last_data_refresh',
              DateTime.now().toIso8601String(),
            );
            await validate();
          }),
        );
      },
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
      lastDataRefresh: repo is DataRefreshMetadataRepository
          ? await (repo as DataRefreshMetadataRepository).lastDataRefresh()
          : null,
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
    if (_manualRunning) return;
    await _syncPendingChanges(state.requireValue, force: true);
    if (!ref.mounted || !state.requireValue.isOnline) return;
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

  bool _manualRunning = false;
  Future<void>? _manualRefresh;
  Future<void> refreshData() => _manualRefresh ??= _refreshData().whenComplete(
    () => _manualRefresh = null,
  );

  Future<void> _refreshData() async {
    final value = state.value ?? await future;
    if (!value.isOnline || value.manualOffline) return;
    _manualRunning = true;
    state = AsyncData(
      state.requireValue.copyWith(isSyncing: true, isRefreshing: true),
    );
    final repository = ref.read(syncRepositoryProvider);
    try {
      final worker = await ref.read(manualDataRefreshFactoryProvider)();
      final result = await worker.refresh();
      if (ref.mounted) {
        final date = repository is DataRefreshMetadataRepository
            ? await (repository as DataRefreshMetadataRepository)
                  .lastDataRefresh()
            : null;
        if (ref.mounted) {
          state = AsyncData(
            state.requireValue.copyWith(
              refreshResult: result,
              lastDataRefresh: date,
            ),
          );
        }
      }
    } catch (error) {
      if (ref.mounted) {
        state = AsyncData(
          state.requireValue.copyWith(
            refreshResult: ManualRefreshResult({'actualización': error}),
          ),
        );
      }
    } finally {
      try {
        if (ref.mounted) {
          final pending = await repository.pendingCount();
          if (ref.mounted) {
            state = AsyncData(
              state.requireValue.copyWith(pendingChanges: pending),
            );
          }
        }
      } catch (error) {
        if (ref.mounted) {
          state = AsyncData(
            state.requireValue.copyWith(
              refreshResult: ManualRefreshResult({'pendientes': error}),
            ),
          );
        }
      } finally {
        _manualRunning = false;
        if (ref.mounted) {
          state = AsyncData(
            state.requireValue.copyWith(isSyncing: false, isRefreshing: false),
          );
        }
      }
    }
  }

  Future<void> syncPendingIfOnline() async {
    // The first save can arrive before this notifier has finished building.
    final value = state.value ?? await future;
    if (!ref.mounted || value.isSyncing || _manualRunning) return;

    final repository = ref.read(syncRepositoryProvider);
    final pendingChanges = await repository.pendingCount();

    if (!ref.mounted || state.value?.isSyncing == true) return;
    final refreshed = state.requireValue.copyWith(
      pendingChanges: pendingChanges,
    );
    state = AsyncData(refreshed);

    await _syncPendingChanges(refreshed);
  }

  Future<void> _syncPendingChanges(
    SyncState value, {
    bool force = false,
  }) async {
    if (!value.isOnline ||
        (!force && value.pendingChanges == 0) ||
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
            isSyncing: _manualRunning,
            pendingChanges: pending,
            lastSync: lastSync,
          ),
        );
        if (ref.exists(animalViewModelProvider)) {
          await ref.read(animalViewModelProvider.notifier).reloadLocal();
        }
        if (ref.mounted && ref.exists(paddockViewModelProvider)) {
          await ref.read(paddockViewModelProvider.notifier).reload();
        }
      }
    }
  }
}
