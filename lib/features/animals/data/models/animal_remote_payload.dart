/// Remote whitelist shared by direct saves and the existing outbox.
/// Local and legacy photo fields are intentionally never read.
abstract final class AnimalRemotePayload {
  static Map<String, Object?> fromLocal(
    Map<String, Object?> payload,
    String userId,
  ) => {
    'id': payload['id'],
    'user_id': userId,
    'code': payload['code'],
    'name': payload['name'],
    'type': payload['type'],
    'breed': payload['breed'],
    'sex': payload['sex'],
    'remote_photo_path': validatedPhotoPath(
      payload['remotePhotoPath'],
      userId,
      payload['id'],
    ),
    'birth_date': payload['birthDate'],
    'weight': payload['weight'],
    'paddock_id': payload['paddockId'],
    'notes': payload['notes'],
    'status': payload['status'],
    'created_at': payload['createdAt'],
    'updated_at': payload['updatedAt'],
  };

  /// Fail closed rather than silently publishing a malformed object reference.
  static String? validatedPhotoPath(
    Object? value,
    String userId,
    Object? animalId,
  ) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException('Invalid remote photo path');
    }
    final parts = value.split('/');
    if (parts.length != 3 ||
        parts[0] != userId ||
        parts[1] != animalId ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.[a-zA-Z0-9]+$',
        ).hasMatch(parts[2])) {
      throw const FormatException('Invalid remote photo path');
    }
    return value;
  }
}
