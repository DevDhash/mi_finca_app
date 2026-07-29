import 'package:mi_finca_app/core/domain/sync_status.dart';

class Paddock {
  const Paddock({
    required this.id,
    required this.name,
    required this.areaHectares,
    String? grassType,
    String? pastureType,
    this.requiredRestDays,
    this.rotationOrder,
    this.grazingStartDate,
    this.plannedGrazingDays,
    this.status = 'Disponible',
    DateTime? lastUsedAt,
    DateTime? lastGrazingEndDate,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.pending,
  }) : pastureType = pastureType ?? grassType,
       lastGrazingEndDate = lastGrazingEndDate ?? lastUsedAt;

  final String id;
  final String name;
  final double areaHectares;
  final String? pastureType;
  final int? requiredRestDays;
  final int? rotationOrder;
  final DateTime? grazingStartDate;
  final int? plannedGrazingDays;
  final String status;
  final DateTime? lastGrazingEndDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  String get grassType => pastureType ?? '';
  DateTime? get lastUsedAt => lastGrazingEndDate;

  Paddock copyWith({
    String? name,
    double? areaHectares,
    String? grassType,
    String? pastureType,
    int? requiredRestDays,
    int? rotationOrder,
    DateTime? grazingStartDate,
    int? plannedGrazingDays,
    String? status,
    DateTime? lastUsedAt,
    DateTime? lastGrazingEndDate,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) => Paddock(
    id: id,
    name: name ?? this.name,
    areaHectares: areaHectares ?? this.areaHectares,
    pastureType: pastureType ?? grassType ?? this.pastureType,
    requiredRestDays: requiredRestDays ?? this.requiredRestDays,
    rotationOrder: rotationOrder ?? this.rotationOrder,
    grazingStartDate: grazingStartDate ?? this.grazingStartDate,
    plannedGrazingDays: plannedGrazingDays ?? this.plannedGrazingDays,
    status: status ?? this.status,
    lastGrazingEndDate:
        lastGrazingEndDate ?? lastUsedAt ?? this.lastGrazingEndDate,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncStatus: syncStatus ?? this.syncStatus,
  );
}
