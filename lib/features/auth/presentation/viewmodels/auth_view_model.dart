import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';
import 'package:mi_finca_app/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:mi_finca_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mi_finca_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:uuid/uuid.dart';

final authLocalDataSourceProvider = Provider(
  (ref) => AuthLocalDataSource(ref.watch(databaseProvider)),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(ref.watch(authLocalDataSourceProvider)),
);
final authViewModelProvider =
    AsyncNotifierProvider<AuthViewModel, UserSession?>(AuthViewModel.new);

class AuthViewModel extends AsyncNotifier<UserSession?> {
  @override
  Future<UserSession?> build() =>
      ref.watch(authRepositoryProvider).currentSession();

  Future<void> login({
    required String email,
    required String password,
    String? name,
  }) async {
    if (email.trim().isEmpty || password.length < 4) {
      throw const FormatException(
        'Ingresa un correo y una clave de al menos 4 caracteres.',
      );
    }
    final session = UserSession(
      id: const Uuid().v4(),
      name: name?.trim().isNotEmpty == true
          ? name!.trim()
          : email.split('@').first,
      email: email.trim(),
    );
    await ref.read(authRepositoryProvider).saveSession(session);
    state = AsyncData(session);
  }

  Future<void> setSession(UserSession session) async {
    await ref.read(authRepositoryProvider).saveSession(session);
    state = AsyncData(session);
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncData(null);
  }
}
