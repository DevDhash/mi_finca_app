typedef Json = Map<String, Object?>;

enum SyncStatus { pending, synced }

class UserSession {
  const UserSession({
    required this.id,
    required this.name,
    required this.email,
  });
  final String id;
  final String name;
  final String email;

  Json toJson() => {'id': id, 'name': name, 'email': email};
  factory UserSession.fromJson(Json json) => UserSession(
    id: json['id']! as String,
    name: json['name']! as String,
    email: json['email']! as String,
  );
}

class Farm {
  const Farm({required this.id, required this.name, required this.location});
  final String id;
  final String name;
  final String location;

  Json toJson() => {'id': id, 'name': name, 'location': location};
  factory Farm.fromJson(Json json) => Farm(
    id: json['id']! as String,
    name: json['name']! as String,
    location: json['location']! as String,
  );
}

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

  Json toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'type': type,
    'breed': breed,
    'sex': sex,
    'photoPath': photoPath,
    'birthDate': birthDate?.toIso8601String(),
    'weight': weight,
    'paddockId': paddockId,
    'notes': notes,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'syncStatus': syncStatus.name,
  };

  factory Animal.fromJson(Json json) => Animal(
    id: json['id']! as String,
    code: json['code']! as String,
    name: json['name'] as String?,
    type: json['type']! as String,
    breed: json['breed']! as String,
    sex: json['sex']! as String,
    photoPath: json['photoPath'] as String?,
    birthDate: json['birthDate'] == null
        ? null
        : DateTime.parse(json['birthDate']! as String),
    weight: (json['weight'] as num?)?.toDouble(),
    paddockId: json['paddockId'] as String?,
    notes: json['notes'] as String? ?? '',
    status: json['status'] as String? ?? 'Activo',
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    syncStatus: SyncStatus.values.byName(
      json['syncStatus'] as String? ?? 'pending',
    ),
  );
}

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
  Json toJson() => {
    'id': id,
    'name': name,
    'areaHectares': areaHectares,
    'grassType': grassType,
    'status': status,
    'lastUsedAt': lastUsedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'syncStatus': syncStatus.name,
  };
  factory Paddock.fromJson(Json json) => Paddock(
    id: json['id']! as String,
    name: json['name']! as String,
    areaHectares: (json['areaHectares']! as num).toDouble(),
    grassType: json['grassType']! as String,
    status: json['status'] as String? ?? 'Disponible',
    lastUsedAt: json['lastUsedAt'] == null
        ? null
        : DateTime.parse(json['lastUsedAt']! as String),
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    syncStatus: SyncStatus.values.byName(
      json['syncStatus'] as String? ?? 'pending',
    ),
  );
}

class Expense {
  const Expense({
    required this.id,
    required this.category,
    required this.amount,
    required this.date,
    this.note = '',
    required this.updatedAt,
    this.syncStatus = SyncStatus.pending,
  });
  final String id;
  final String category;
  final double amount;
  final DateTime date;
  final String note;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  Json toJson() => {
    'id': id,
    'category': category,
    'amount': amount,
    'date': date.toIso8601String(),
    'note': note,
    'updatedAt': updatedAt.toIso8601String(),
    'syncStatus': syncStatus.name,
  };
  factory Expense.fromJson(Json json) => Expense(
    id: json['id']! as String,
    category: json['category']! as String,
    amount: (json['amount']! as num).toDouble(),
    date: DateTime.parse(json['date']! as String),
    note: json['note'] as String? ?? '',
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    syncStatus: SyncStatus.values.byName(
      json['syncStatus'] as String? ?? 'pending',
    ),
  );
}

class Movement {
  const Movement({
    required this.id,
    required this.animalId,
    this.fromPaddockId,
    required this.toPaddockId,
    required this.date,
  });
  final String id;
  final String animalId;
  final String? fromPaddockId;
  final String toPaddockId;
  final DateTime date;
  Json toJson() => {
    'id': id,
    'animalId': animalId,
    'fromPaddockId': fromPaddockId,
    'toPaddockId': toPaddockId,
    'date': date.toIso8601String(),
  };
  factory Movement.fromJson(Json json) => Movement(
    id: json['id']! as String,
    animalId: json['animalId']! as String,
    fromPaddockId: json['fromPaddockId'] as String?,
    toPaddockId: json['toPaddockId']! as String,
    date: DateTime.parse(json['date']! as String),
  );
}
