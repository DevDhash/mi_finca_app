import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AnimalPhotoStorage {
  String? get currentUserId;

  /// The same path always denotes the same bytes. Never overwrites an object.
  Future<void> ensureUploaded({
    required String ownerId,
    required String objectPath,
    required Uint8List bytes,
    required String digest,
    required String contentType,
  });
}

class SupabaseAnimalPhotoStorage implements AnimalPhotoStorage {
  const SupabaseAnimalPhotoStorage(this._client);
  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  void _requireOwner(String ownerId) {
    if (currentUserId != ownerId || _client.auth.currentSession == null) {
      throw const AuthException('Inicia sesión con la cuenta de esta foto.');
    }
  }

  @override
  Future<void> ensureUploaded({
    required String ownerId,
    required String objectPath,
    required Uint8List bytes,
    required String digest,
    required String contentType,
  }) async {
    _requireOwner(ownerId);
    if (!objectPath.startsWith('$ownerId/')) {
      throw const FormatException('La foto no pertenece a esta cuenta.');
    }
    final bucket = _client.storage.from('animal-photos');
    try {
      await bucket.uploadBinary(
        objectPath,
        bytes,
        fileOptions: FileOptions(
          upsert: false,
          contentType: contentType,
          metadata: {'sha256': digest},
        ),
        retryAttempts: 0,
      );
    } on StorageException catch (error) {
      // A lost successful response yields a duplicate on the next attempt.
      // Do not treat permissions, server errors or an arbitrary 400 as success.
      if (error.error != 'Duplicate' &&
          error.error != 'ResourceAlreadyExists' &&
          error.error != 'KeyAlreadyExists') {
        rethrow;
      }
      _requireOwner(ownerId);
      final existing = await bucket.info(objectPath);
      if (existing.size != bytes.length ||
          existing.metadata?['sha256'] != digest) {
        throw const FormatException(
          'El objeto existente no coincide con la foto.',
        );
      }
    }
    _requireOwner(ownerId);
  }
}
