import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';

abstract interface class AuthRepository {
  Future<UserSession?> currentSession();
  Future<void> saveSession(UserSession session);
  Future<void> signOut();
}
