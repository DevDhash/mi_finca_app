import 'package:mi_finca_app/features/animals/data/models/animal_remote_payload.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AnimalPhotoUrlSource {
  String? get currentUserId;
  Stream<String?> get authChanges;
  Future<String> sign(String animalId, String objectPath, int expiresIn);
}

class SupabaseAnimalPhotoUrlSource implements AnimalPhotoUrlSource {
  const SupabaseAnimalPhotoUrlSource(this._client);
  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;
  @override
  Stream<String?> get authChanges =>
      _client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  @override
  Future<String> sign(String animalId, String objectPath, int expiresIn) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw const AuthException('Inicia sesión para ver la foto.');
    }
    AnimalRemotePayload.validatedPhotoPath(
      objectPath,
      session.user.id,
      animalId,
    );
    final url = await _client.storage
        .from('animal-photos')
        .createSignedUrl(objectPath, expiresIn);
    if (_client.auth.currentSession?.accessToken != session.accessToken) {
      throw const AuthException(
        'La sesión cambió mientras se cargaba la foto.',
      );
    }
    return url;
  }
}
