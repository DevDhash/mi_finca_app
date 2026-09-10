import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FarmRemoteDataSource {
  const FarmRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<void> upsertFarm(Farm farm) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw const AuthException('No hay usuario autenticado.');
    }

    await _client.from('farms').upsert({
      'id': farm.id,
      'user_id': user.id,
      'name': farm.name,
      'location': farm.location,
    });
  }

  Future<Farm?> readCurrentUserFarm() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw const AuthException('No hay usuario autenticado.');
    }

    final response = await _client
        .from('farms')
        .select('id, name, location')
        .eq('user_id', user.id)
        .isFilter('deleted_at', null)
        .maybeSingle();

    if (response == null) return null;

    return Farm(
      id: response['id'] as String,
      name: response['name'] as String,
      location: response['location'] as String,
    );
  }
}
