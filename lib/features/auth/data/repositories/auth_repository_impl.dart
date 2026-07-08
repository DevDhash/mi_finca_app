import 'package:mi_finca_app/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:mi_finca_app/features/auth/data/datasources/supabase_auth_datasource.dart';
import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';
import 'package:mi_finca_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required AuthLocalDataSource local,
    required SupabaseAuthDatasource remote,
  }) : _local = local,
       _remote = remote;

  final AuthLocalDataSource _local;
  final SupabaseAuthDatasource _remote;

  @override
  Future<UserSession?> currentSession() async {
    final remoteUser = _remote.currentUser;

    if (remoteUser != null) {
      final session = _mapSupabaseUserToSession(remoteUser);
      await _local.writeSession(session);
      return session;
    }

    return _local.readSession();
  }

  @override
  Future<UserSession> login({
    required String email,
    required String password,
    String? name,
  }) async {
    try {
      final response = await _remote.signIn(email: email, password: password);

      final user = response.user;

      if (user == null) {
        throw const AuthException('No se pudo iniciar sesión.');
      }

      final session = _mapSupabaseUserToSession(user);
      await _local.writeSession(session);
      return session;
    } on AuthException catch (error) {
      final shouldTryRegister =
          name != null &&
          name.trim().isNotEmpty &&
          _isInvalidCredentials(error.message);

      if (!shouldTryRegister) {
        throw AuthException(_friendlyAuthMessage(error.message));
      }

      return signUp(email: email, password: password, name: name.trim());
    }
  }

  @override
  Future<UserSession> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final response = await _remote.signUp(
      email: email,
      password: password,
      name: name,
    );

    final user = response.user;

    if (user == null) {
      throw const AuthException('No se pudo crear la cuenta.');
    }

    final session = _mapSupabaseUserToSession(user);
    await _local.writeSession(session);
    return session;
  }

  @override
  Future<void> saveSession(UserSession session) {
    return _local.writeSession(session);
  }

  @override
  Future<void> signOut() async {
    await _remote.signOut();
    await _local.deleteSession();
  }

  UserSession _mapSupabaseUserToSession(User user) {
    final metadataName = user.userMetadata?['name']?.toString();
    final email = user.email ?? '';

    return UserSession(
      id: user.id,
      name: metadataName?.trim().isNotEmpty == true
          ? metadataName!.trim()
          : email.split('@').first,
      email: email,
    );
  }

  bool _isInvalidCredentials(String message) {
    final normalized = message.toLowerCase();

    return normalized.contains('invalid login credentials') ||
        normalized.contains('invalid credentials') ||
        normalized.contains('email not confirmed');
  }

  String _friendlyAuthMessage(String message) {
    final normalized = message.toLowerCase();

    if (normalized.contains('invalid login credentials') ||
        normalized.contains('invalid credentials')) {
      return 'Correo o contraseña incorrectos.';
    }

    if (normalized.contains('email not confirmed')) {
      return 'Debes confirmar tu correo antes de iniciar sesión.';
    }

    if (normalized.contains('user already registered') ||
        normalized.contains('already registered')) {
      return 'Este correo ya está registrado. Inicia sesión.';
    }

    return message;
  }
}
