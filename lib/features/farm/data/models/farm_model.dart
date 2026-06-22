import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';

abstract final class FarmModel {
  static Map<String, Object?> toJson(Farm value) => {
    'id': value.id,
    'name': value.name,
    'location': value.location,
  };
  static Farm fromJson(Map<String, Object?> json) => Farm(
    id: json['id']! as String,
    name: json['name']! as String,
    location: json['location']! as String,
  );
}
