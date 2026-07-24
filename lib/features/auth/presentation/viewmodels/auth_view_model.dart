import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:mi_finca_app/features/auth/data/datasources/supabase_auth_datasource.dart';
import 'package:mi_finca_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';
import 'package:mi_finca_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:mi_finca_app/features/farm/presentation/viewmodels/farm_view_model.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authLocalDataSourceProvider = Provider(
  (ref) => AuthLocalDataSource(ref.watch(databaseProvider)),
);

final supabaseAuthDataSourceProvider = Provider(
  (ref) => SupabaseAuthDatasource(Supabase.instance.client),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(
    local: ref.watch(authLocalDataSourceProvider),
    remote: ref.watch(supabaseAuthDataSourceProvider),
  ),
);

final authViewModelProvider =
    AsyncNotifierProvider<AuthViewModel, UserSession?>(AuthViewModel.new);

class AuthViewModel extends AsyncNotifier<UserSession?> {
  @override
  Future<UserSession?> build() {
    return ref.watch(authRepositoryProvider).currentSession();
  }

  Future<void> login({
    required String email,
    required String password,
    String? name,
  }) async {
    final cleanEmail = email.trim();
    final cleanPassword = password;
    final cleanName = name?.trim();

    if (cleanEmail.isEmpty || cleanPassword.length < 6) {
      throw const FormatException(
        'Ingresa un correo y una clave de al menos 6 caracteres.',
      );
    }

    final session = await ref
        .read(authRepositoryProvider)
        .login(email: cleanEmail, password: cleanPassword, name: cleanName);

    _invalidateUserDataProviders();
    state = AsyncData(session);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final cleanEmail = email.trim();
    final cleanPassword = password;
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw const FormatException('Ingresa tu nombre.');
    }

    if (cleanEmail.isEmpty || cleanPassword.length < 6) {
      throw const FormatException(
        'Ingresa un correo y una clave de al menos 6 caracteres.',
      );
    }

    final session = await ref
        .read(authRepositoryProvider)
        .signUp(email: cleanEmail, password: cleanPassword, name: cleanName);

    _invalidateUserDataProviders();
    state = AsyncData(session);
  }

  Future<void> setSession(UserSession session) async {
    await ref.read(authRepositoryProvider).saveSession(session);
    _invalidateUserDataProviders();
    state = AsyncData(session);
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncData(null);
    _invalidateUserDataProviders();
  }

  void _invalidateUserDataProviders() {
    ref.invalidate(farmViewModelProvider);
    ref.invalidate(animalViewModelProvider);
    ref.invalidate(paddockViewModelProvider);
    ref.invalidate(expenseViewModelProvider);
    ref.invalidate(syncViewModelProvider);
  }
}
