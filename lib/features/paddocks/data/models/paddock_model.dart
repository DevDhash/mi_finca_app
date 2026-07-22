import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';

abstract final class PaddockModel {
  static Map<String, Object?> toJson(Paddock v) => {
    'id': v.id,
    'name': v.name,
    'areaHectares': v.areaHectares,

    // Nuevos nombres de dominio.
    'pastureType': v.pastureType,
    'requiredRestDays': v.requiredRestDays,
    'lastGrazingEndDate': v.lastGrazingEndDate?.toIso8601String(),

    // Alias legacy locales para compatibilidad con datos/pantallas previas.
    // No implican que Supabase deba seguir usando estas columnas.
    'grassType': v.grassType,
    'lastUsedAt': v.lastUsedAt?.toIso8601String(),

    'status': v.status,
    'createdAt': v.createdAt.toIso8601String(),
    'updatedAt': v.updatedAt.toIso8601String(),
    'syncStatus': v.syncStatus.name,
  };

  static Paddock fromJson(Map<String, Object?> j) => Paddock(
    id: j['id']! as String,
    name: j['name']! as String,
    areaHectares: (j['areaHectares']! as num).toDouble(),
    pastureType: (j['pastureType'] ?? j['grassType']) as String?,
    requiredRestDays: (j['requiredRestDays'] as num?)?.toInt(),
    status: j['status'] as String? ?? 'Disponible',
    lastGrazingEndDate: (j['lastGrazingEndDate'] ?? j['lastUsedAt']) == null
        ? null
        : DateTime.parse(
            (j['lastGrazingEndDate'] ?? j['lastUsedAt'])! as String,
          ),
    createdAt: DateTime.parse(j['createdAt']! as String),
    updatedAt: DateTime.parse(j['updatedAt']! as String),
    syncStatus: SyncStatus.values.byName(
      j['syncStatus'] as String? ?? 'pending',
    ),
  );
}
