import 'package:mi_finca_app/core/domain/sync_status.dart';

class Animal {
  const Animal({
    required this.id,
    required this.code,
    this.name,
    required this.type,
    required this.breed,
    required this.sex,
    this.photoPath,
    this.birthDate,
    this.weight,
    this.paddockId,
    this.notes = '',
    this.status = 'Activo',
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.pending,
  });
  final String id;
  final String code;
  final String? name;
  final String type;
  final String breed;
  final String sex;
  final String? photoPath;
  final DateTime? birthDate;
  final double? weight;
  final String? paddockId;
  final String notes;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  String get displayName => (name?.trim().isNotEmpty ?? false) ? name! : code;
  Animal copyWith({
    String? code,
    String? name,
    String? type,
    String? breed,
    String? sex,
    String? photoPath,
    DateTime? birthDate,
    double? weight,
    String? paddockId,
    String? notes,
    String? status,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) => Animal(
    id: id,
    code: code ?? this.code,
    name: name ?? this.name,
    type: type ?? this.type,
    breed: breed ?? this.breed,
    sex: sex ?? this.sex,
    photoPath: photoPath ?? this.photoPath,
    birthDate: birthDate ?? this.birthDate,
    weight: weight ?? this.weight,
    paddockId: paddockId ?? this.paddockId,
    notes: notes ?? this.notes,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncStatus: syncStatus ?? this.syncStatus,
  );
}
