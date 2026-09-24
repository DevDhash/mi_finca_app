import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

/// Local-only durable intent. Never part of a Supabase animals payload.
abstract final class AnimalPhotoUpload {
  static const key = '_photoUpload';

  static Map<String, Object?>? read(Map<String, Object?> payload) {
    final value = payload[key];
    return value is Map ? Map<String, Object?>.from(value) : null;
  }

  static String? localPath(Map<String, Object?> payload) =>
      (payload.containsKey('localPhotoPath')
              ? payload['localPhotoPath']
              : payload['photoPath'])
          as String?;

  static Map<String, Object?> create(String localPath, String? ownerId) {
    final extension = path
        .extension(localPath)
        .replaceFirst('.', '')
        .toLowerCase();
    return {
      'version': const Uuid().v4(),
      'localPath': localPath,
      'ownerId': ownerId,
      'extension': RegExp(r'^[a-z0-9]+$').hasMatch(extension)
          ? extension
          : 'jpg',
      'status': 'pending',
    };
  }
}
