import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_local_datasource.dart';
import 'package:mi_finca_app/features/paddocks/data/repositories/paddock_repository_impl.dart';
import 'package:mi_finca_app/features/paddocks/domain/repositories/paddock_repository.dart';

final paddockLocalDataSourceProvider = Provider(
  (ref) => PaddockLocalDataSource(ref.watch(databaseProvider)),
);
final paddockRepositoryProvider = Provider<PaddockRepository>(
  (ref) => PaddockRepositoryImpl(ref.watch(paddockLocalDataSourceProvider)),
);
final paddockViewModelProvider =
    AsyncNotifierProvider<PaddockViewModel, List<Paddock>>(
      PaddockViewModel.new,
    );

class PaddockViewModel extends AsyncNotifier<List<Paddock>> {
  @override
  Future<List<Paddock>> build() =>
      ref.watch(paddockRepositoryProvider).getAll();
  Future<void> save(Paddock paddock) async {
    await ref.read(paddockRepositoryProvider).save(paddock);
    final items = [...state.requireValue];
    final index = items.indexWhere((item) => item.id == paddock.id);
    if (index < 0) {
      items.insert(0, paddock);
    } else {
      items[index] = paddock;
    }
    state = AsyncData(items);
  }

  Future<void> reload() async =>
      state = AsyncData(await ref.read(paddockRepositoryProvider).getAll());
}
