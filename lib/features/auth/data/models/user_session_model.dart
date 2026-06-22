import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';

abstract final class UserSessionModel {
  static Map<String, Object?> toJson(UserSession value) => {
    'id': value.id,
    'name': value.name,
    'email': value.email,
  };
  static UserSession fromJson(Map<String, Object?> json) => UserSession(
    id: json['id']! as String,
    name: json['name']! as String,
    email: json['email']! as String,
  );
}
