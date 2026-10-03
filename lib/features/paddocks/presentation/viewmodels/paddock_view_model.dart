import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_patch.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_local_datasource.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_remote_datasource.dart';
import 'package:mi_finca_app/features/paddocks/data/repositories/paddock_repository_impl.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/repositories/paddock_repository.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final paddockLocalDataSourceProvider = Provider(
  (ref) => PaddockLocalDataSource(ref.watch(databaseProvider)),
);

final paddockRemoteDataSourceProvider = Provider(
  (ref) => PaddockRemoteDataSource(Supabase.instance.client),
);

final paddockRepositoryProvider = Provider<PaddockRepository>(
  (ref) => PaddockRepositoryImpl(
    local: ref.watch(paddockLocalDataSourceProvider),
    remote: ref.watch(paddockRemoteDataSourceProvider),
  ),
);

final paddockViewModelProvider =
    AsyncNotifierProvider<PaddockViewModel, List<Paddock>>(
      PaddockViewModel.new,
    );

class PaddockViewModel extends AsyncNotifier<List<Paddock>> {
  @override
  Future<List<Paddock>> build() {
    return ref.watch(paddockRepositoryProvider).getAll();
  }

  /// Full snapshots are only for creation. Existing edits must carry intent.
  Future<void> save(Paddock paddock) async {
    if (state.requireValue.any((p) => p.id == paddock.id)) {
      throw StateError('Usa un patch explícito para editar el potrero.');
    }
    await ref.read(paddockRepositoryProvider).save(paddock);
    await reload();
    unawaited(ref.read(syncViewModelProvider.notifier).syncPendingIfOnline());
  }

  Future<void> deletePaddock(String id) async {
    final database = ref.read(databaseProvider);
    final owner = await database.localOwner();
    if (owner == null) throw StateError('Sesión requerida');
    await database.markDeleted('paddocks', id, owner);
    await reload();
    if (ref.mounted) {
      unawaited(ref.read(syncViewModelProvider.notifier).syncPendingIfOnline());
    }
  }

  Future<void> edit(String id, PaddockPatch patch) async {
    final repository = ref.read(paddockRepositoryProvider);
    if (repository is! PaddockEditRepository) {
      throw StateError('Patches no soportados');
    }
    await (repository as PaddockEditRepository).edit(id, patch);
    await reload();
    unawaited(ref.read(syncViewModelProvider.notifier).syncPendingIfOnline());
  }

  Future<void> updateRotationOrder(List<String> ids) async {
    final repository = ref.read(paddockRepositoryProvider);
    if (repository is! PaddockEditRepository) {
      throw StateError('Patches no soportados');
    }
    await ref.read(databaseProvider).runInTransaction(() async {
      for (var i = 0; i < ids.length; i++) {
        await (repository as PaddockEditRepository).edit(
          ids[i],
          PaddockPatch({PaddockField.rotationOrder: i + 1}),
        );
      }
    });
    await reload();
    unawaited(ref.read(syncViewModelProvider.notifier).syncPendingIfOnline());
  }

  void applyPersistedMovementUpdates(List<Paddock> updatedPaddocks) {
    final updatedById = {
      for (final paddock in updatedPaddocks) paddock.id: paddock,
    };
    state = AsyncData(
      state.requireValue
          .map((paddock) => updatedById[paddock.id] ?? paddock)
          .toList(),
    );
  }

  Future<void> reload() async {
    state = AsyncData(await ref.read(paddockRepositoryProvider).getAll());
  }
}
