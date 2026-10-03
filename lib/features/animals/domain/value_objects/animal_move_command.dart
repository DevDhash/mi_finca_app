class AnimalMoveCommand {
  const AnimalMoveCommand({
    required this.movementId,
    required this.ownerId,
    required this.animalId,
    required this.fromPaddockId,
    required this.toPaddockId,
    required this.movedAt,
    this.plannedGrazingDays,
  });

  final String movementId;
  final String ownerId;
  final String animalId;
  final String? fromPaddockId;
  final String toPaddockId;
  final DateTime movedAt;
  final int? plannedGrazingDays;

  Map<String, Object?> toLocal() => {
    'movementId': movementId,
    'ownerId': ownerId,
    'animalId': animalId,
    'fromPaddockId': fromPaddockId,
    'toPaddockId': toPaddockId,
    'movedAt': movedAt.toUtc().toIso8601String(),
    'plannedGrazingDays': plannedGrazingDays,
    'state': 'pending',
  };

  factory AnimalMoveCommand.fromLocal(Map<String, Object?> value) {
    final movementId = value['movementId'];
    final ownerId = value['ownerId'];
    final animalId = value['animalId'];
    final toPaddockId = value['toPaddockId'];
    final movedAt = value['movedAt'];
    final planned = value['plannedGrazingDays'];

    if (movementId is! String ||
        movementId.isEmpty ||
        ownerId is! String ||
        ownerId.isEmpty ||
        animalId is! String ||
        animalId.isEmpty ||
        toPaddockId is! String ||
        toPaddockId.isEmpty ||
        movedAt is! String ||
        (value['fromPaddockId'] != null && value['fromPaddockId'] is! String) ||
        (planned != null && planned is! int)) {
      throw const FormatException('Invalid AnimalMoveCommand');
    }

    return AnimalMoveCommand(
      movementId: movementId,
      ownerId: ownerId,
      animalId: animalId,
      fromPaddockId: value['fromPaddockId'] as String?,
      toPaddockId: toPaddockId,
      movedAt: DateTime.parse(movedAt),
      plannedGrazingDays: planned as int?,
    );
  }
}
