/// Explicit form intent. This is not a durable MOVE command and cannot be
/// published as an ordinary animal edit.
class AnimalLocationMoveIntent {
  const AnimalLocationMoveIntent({
    required this.animalId,
    required this.expectedFromPaddockId,
    required this.toPaddockId,
  });

  final String animalId;
  final String? expectedFromPaddockId;
  final String? toPaddockId;
}

class AnimalLocationMoveRequired implements Exception {
  const AnimalLocationMoveRequired(this.intent);

  final AnimalLocationMoveIntent intent;
}

/// Fail before saving any part of a form that also requests a move. Full D2
/// must replace this boundary with atomic coordination of edit and MOVE intent.
Future<void> saveAnimalFormWithoutMove({
  required AnimalLocationMoveIntent? locationIntent,
  required Future<void> Function() persist,
}) async {
  if (locationIntent != null) {
    throw AnimalLocationMoveRequired(locationIntent);
  }
  await persist();
}
