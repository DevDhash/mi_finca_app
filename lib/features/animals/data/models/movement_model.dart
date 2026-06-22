import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';

abstract final class MovementModel {
  static Map<String, Object?> toJson(Movement v) => {
    'id': v.id,
    'animalId': v.animalId,
    'fromPaddockId': v.fromPaddockId,
    'toPaddockId': v.toPaddockId,
    'date': v.date.toIso8601String(),
  };
  static Movement fromJson(Map<String, Object?> j) => Movement(
    id: j['id']! as String,
    animalId: j['animalId']! as String,
    fromPaddockId: j['fromPaddockId'] as String?,
    toPaddockId: j['toPaddockId']! as String,
    date: DateTime.parse(j['date']! as String),
  );
}
