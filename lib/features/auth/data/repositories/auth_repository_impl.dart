import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';
import 'package:mi_finca_app/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:mi_finca_app/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._local);
  final AuthLocalDataSource _local;
  @override
  Future<UserSession?> currentSession() => _local.readSession();
  @override
  Future<void> saveSession(UserSession session) => _local.writeSession(session);
  @override
  Future<void> signOut() => _local.deleteSession();
}
