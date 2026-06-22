import 'package:mi_finca_app/core/domain/sync_status.dart';

class Paddock {
  const Paddock({
    required this.id,
    required this.name,
    required this.areaHectares,
    required this.grassType,
    this.status = 'Disponible',
    this.lastUsedAt,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.pending,
  });
  final String id;
  final String name;
  final double areaHectares;
  final String grassType;
  final String status;
  final DateTime? lastUsedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  int get restDays =>
      lastUsedAt == null ? 0 : DateTime.now().difference(lastUsedAt!).inDays;
  Paddock copyWith({
    String? name,
    double? areaHectares,
    String? grassType,
    String? status,
    DateTime? lastUsedAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) => Paddock(
    id: id,
    name: name ?? this.name,
    areaHectares: areaHectares ?? this.areaHectares,
    grassType: grassType ?? this.grassType,
    status: status ?? this.status,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncStatus: syncStatus ?? this.syncStatus,
  );
}
