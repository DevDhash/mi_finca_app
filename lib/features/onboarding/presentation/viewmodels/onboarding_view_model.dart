import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:mi_finca_app/features/farm/presentation/viewmodels/farm_view_model.dart';
import 'package:mi_finca_app/features/onboarding/domain/usecases/configure_farm.dart';
import 'package:mi_finca_app/features/onboarding/domain/usecases/load_demo_data.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';

final configureFarmProvider = Provider(
  (ref) => ConfigureFarm(
    ref.watch(farmRepositoryProvider),
    ref.watch(paddockRepositoryProvider),
  ),
);
final loadDemoDataProvider = Provider(
  (ref) => LoadDemoData(
    ref.watch(databaseProvider),
    ref.watch(authRepositoryProvider),
    ref.watch(farmRepositoryProvider),
    ref.watch(animalRepositoryProvider),
    ref.watch(paddockRepositoryProvider),
    ref.watch(expenseRepositoryProvider),
  ),
);
final onboardingViewModelProvider =
    AsyncNotifierProvider<OnboardingViewModel, void>(OnboardingViewModel.new);

class OnboardingViewModel extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}
  Future<void> configure(
    String name,
    String location,
    String firstPaddock,
  ) async {
    state = const AsyncLoading();
    final farm = await ref.read(configureFarmProvider)(
      name,
      location,
      firstPaddock,
    );
    ref.read(farmViewModelProvider.notifier).setCurrent(farm);
    ref.invalidate(paddockViewModelProvider);
    ref.invalidate(syncViewModelProvider);
    state = const AsyncData(null);
  }

  Future<void> loadDemo() async {
    state = const AsyncLoading();
    await ref.read(loadDemoDataProvider)();
    ref.invalidate(authViewModelProvider);
    ref.invalidate(farmViewModelProvider);
    ref.invalidate(animalViewModelProvider);
    ref.invalidate(paddockViewModelProvider);
    ref.invalidate(expenseViewModelProvider);
    ref.invalidate(syncViewModelProvider);
    state = const AsyncData(null);
  }
}
