import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';

abstract interface class AuthRepository {
  Future<UserSession?> currentSession();

  Future<UserSession> login({
    required String email,
    required String password,
    String? name,
  });

  Future<UserSession> signUp({
    required String email,
    required String password,
    required String name,
  });

  Future<void> saveSession(UserSession session);

  Future<void> signOut();
}
