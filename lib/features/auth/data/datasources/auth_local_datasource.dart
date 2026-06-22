import 'dart:convert';

import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/auth/data/models/user_session_model.dart';
import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';

class AuthLocalDataSource {
  const AuthLocalDataSource(this._database);
  final AppDatabase _database;

  Future<UserSession?> readSession() async {
    final raw = await _database.readSetting('session');
    return raw == null
        ? null
        : UserSessionModel.fromJson(
            Map<String, Object?>.from(jsonDecode(raw) as Map),
          );
  }

  Future<void> writeSession(UserSession session) => _database.writeSetting(
    'session',
    jsonEncode(UserSessionModel.toJson(session)),
  );

  Future<void> deleteSession() => _database.deleteSetting('session');
}
