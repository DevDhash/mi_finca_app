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

  Future<void> save(Paddock paddock) async {
    final items = [...state.requireValue];
    final now = DateTime.now();

    if (paddock.status == 'En uso') {
      for (var i = 0; i < items.length; i++) {
        final current = items[i];

        if (current.id == paddock.id || current.status != 'En uso') continue;

        final rested = Paddock(
          id: current.id,
          name: current.name,
          areaHectares: current.areaHectares,
          pastureType: current.pastureType,
          requiredRestDays: current.requiredRestDays,
          rotationOrder: current.rotationOrder,
          status: 'Descansando',
          lastGrazingEndDate: now,
          createdAt: current.createdAt,
          updatedAt: now,
        );

        await ref.read(paddockRepositoryProvider).save(rested);
        items[i] = rested;
      }
    }

    await ref.read(paddockRepositoryProvider).save(paddock);

    final index = items.indexWhere((item) => item.id == paddock.id);

    if (index < 0) {
      items.insert(0, paddock);
    } else {
      items[index] = paddock;
    }

    state = AsyncData(items);

    unawaited(ref.read(syncViewModelProvider.notifier).syncPendingIfOnline());
  }

  Future<void> updateRotationOrder(List<String> orderedPaddockIds) async {
    final items = [...state.requireValue];
    final now = DateTime.now();
    final updatedById = <String, Paddock>{};

    for (var i = 0; i < orderedPaddockIds.length; i++) {
      final id = orderedPaddockIds[i];
      Paddock? paddock;
      for (final item in items) {
        if (item.id == id) {
          paddock = item;
          break;
        }
      }

      if (paddock == null) continue;

      updatedById[id] = paddock.copyWith(rotationOrder: i + 1, updatedAt: now);
    }

    final updatedItems = items
        .map((item) => updatedById[item.id] ?? item)
        .toList();

    state = AsyncData(updatedItems);

    for (final paddock in updatedById.values) {
      await ref.read(paddockRepositoryProvider).save(paddock);
    }

    unawaited(ref.read(syncViewModelProvider.notifier).syncPendingIfOnline());
  }

  Future<void> reload() async {
    state = AsyncData(await ref.read(paddockRepositoryProvider).getAll());
  }
}
