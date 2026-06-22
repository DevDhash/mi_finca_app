import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';

abstract final class AnimalModel {
  static Map<String, Object?> toJson(Animal v) => {
    'id': v.id,
    'code': v.code,
    'name': v.name,
    'type': v.type,
    'breed': v.breed,
    'sex': v.sex,
    'photoPath': v.photoPath,
    'birthDate': v.birthDate?.toIso8601String(),
    'weight': v.weight,
    'paddockId': v.paddockId,
    'notes': v.notes,
    'status': v.status,
    'createdAt': v.createdAt.toIso8601String(),
    'updatedAt': v.updatedAt.toIso8601String(),
    'syncStatus': v.syncStatus.name,
  };
  static Animal fromJson(Map<String, Object?> j) => Animal(
    id: j['id']! as String,
    code: j['code']! as String,
    name: j['name'] as String?,
    type: j['type']! as String,
    breed: j['breed']! as String,
    sex: j['sex']! as String,
    photoPath: j['photoPath'] as String?,
    birthDate: j['birthDate'] == null
        ? null
        : DateTime.parse(j['birthDate']! as String),
    weight: (j['weight'] as num?)?.toDouble(),
    paddockId: j['paddockId'] as String?,
    notes: j['notes'] as String? ?? '',
    status: j['status'] as String? ?? 'Activo',
    createdAt: DateTime.parse(j['createdAt']! as String),
    updatedAt: DateTime.parse(j['updatedAt']! as String),
    syncStatus: SyncStatus.values.byName(
      j['syncStatus'] as String? ?? 'pending',
    ),
  );
}
