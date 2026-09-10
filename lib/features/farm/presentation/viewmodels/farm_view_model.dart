import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/farm/data/datasources/farm_local_datasource.dart';
import 'package:mi_finca_app/features/farm/data/datasources/farm_remote_datasource.dart';
import 'package:mi_finca_app/features/farm/data/repositories/farm_repository_impl.dart';
import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';
import 'package:mi_finca_app/features/farm/domain/repositories/farm_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final farmLocalDataSourceProvider = Provider(
  (ref) => FarmLocalDataSource(ref.watch(databaseProvider)),
);

final farmRemoteDataSourceProvider = Provider(
  (ref) => FarmRemoteDataSource(Supabase.instance.client),
);

final farmRepositoryProvider = Provider<FarmRepository>(
  (ref) => FarmRepositoryImpl(
    local: ref.watch(farmLocalDataSourceProvider),
    remote: ref.watch(farmRemoteDataSourceProvider),
  ),
);

final farmViewModelProvider = AsyncNotifierProvider<FarmViewModel, Farm?>(
  FarmViewModel.new,
);

class FarmViewModel extends AsyncNotifier<Farm?> {
  @override
  Future<Farm?> build() {
    return ref.watch(farmRepositoryProvider).getFarm();
  }

  Future<void> save(Farm farm) async {
    await ref.read(farmRepositoryProvider).saveFarm(farm);
    state = AsyncData(farm);
  }

  void setCurrent(Farm farm) {
    state = AsyncData(farm);
  }
}
