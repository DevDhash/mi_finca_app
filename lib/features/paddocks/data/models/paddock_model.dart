import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';

abstract final class PaddockModel {
  static Map<String, Object?> toJson(Paddock v) => {
    'id': v.id,
    'name': v.name,
    'areaHectares': v.areaHectares,
    'grassType': v.grassType,
    'status': v.status,
    'lastUsedAt': v.lastUsedAt?.toIso8601String(),
    'createdAt': v.createdAt.toIso8601String(),
    'updatedAt': v.updatedAt.toIso8601String(),
    'syncStatus': v.syncStatus.name,
  };
  static Paddock fromJson(Map<String, Object?> j) => Paddock(
    id: j['id']! as String,
    name: j['name']! as String,
    areaHectares: (j['areaHectares']! as num).toDouble(),
    grassType: j['grassType']! as String,
    status: j['status'] as String? ?? 'Disponible',
    lastUsedAt: j['lastUsedAt'] == null
        ? null
        : DateTime.parse(j['lastUsedAt']! as String),
    createdAt: DateTime.parse(j['createdAt']! as String),
    updatedAt: DateTime.parse(j['updatedAt']! as String),
    syncStatus: SyncStatus.values.byName(
      j['syncStatus'] as String? ?? 'pending',
    ),
  );
}
