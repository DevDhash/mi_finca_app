import 'package:mi_finca_app/core/domain/sync_status.dart';

const _notProvided = Object();

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
    Object? grassType = _notProvided,
    Object? pastureType = _notProvided,
    Object? requiredRestDays = _notProvided,
    Object? rotationOrder = _notProvided,
    Object? grazingStartDate = _notProvided,
    Object? plannedGrazingDays = _notProvided,
    String? status,
    Object? lastUsedAt = _notProvided,
    Object? lastGrazingEndDate = _notProvided,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) => Paddock(
    id: id,
    name: name ?? this.name,
    areaHectares: areaHectares ?? this.areaHectares,
    pastureType: pastureType != _notProvided
        ? pastureType as String?
        : grassType != _notProvided
        ? grassType as String?
        : this.pastureType,
    requiredRestDays: requiredRestDays == _notProvided
        ? this.requiredRestDays
        : requiredRestDays as int?,
    rotationOrder: rotationOrder == _notProvided
        ? this.rotationOrder
        : rotationOrder as int?,
    grazingStartDate: grazingStartDate == _notProvided
        ? this.grazingStartDate
        : grazingStartDate as DateTime?,
    plannedGrazingDays: plannedGrazingDays == _notProvided
        ? this.plannedGrazingDays
        : plannedGrazingDays as int?,
    status: status ?? this.status,
    lastGrazingEndDate: lastGrazingEndDate != _notProvided
        ? lastGrazingEndDate as DateTime?
        : lastUsedAt != _notProvided
        ? lastUsedAt as DateTime?
        : this.lastGrazingEndDate,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncStatus: syncStatus ?? this.syncStatus,
  );
}
