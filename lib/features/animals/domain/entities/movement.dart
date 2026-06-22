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
}
