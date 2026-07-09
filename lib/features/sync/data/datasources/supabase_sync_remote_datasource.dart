import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseSyncRemoteDataSource implements SyncRemoteDataSource {
  const SupabaseSyncRemoteDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<void> pushRecord(PendingRecord record) async {
    switch (record.collection) {
      case 'paddocks':
        return _pushPaddock(record.payload);
      case 'animals':
        return _pushAnimal(record.payload);
      case 'movements':
        return _pushMovement(record.payload);
      case 'expenses':
        return _pushExpense(record.payload);
      default:
        throw UnsupportedError(
          'Colección no soportada para sync: ${record.collection}',
        );
    }
  }

  Future<String> _currentUserId() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw const AuthException('No hay usuario autenticado.');
    }

    return user.id;
  }

  Future<void> _pushPaddock(Map<String, Object?> payload) async {
    final userId = await _currentUserId();

    await _client.from('paddocks').upsert({
      'id': payload['id'],
      'user_id': userId,
      'name': payload['name'],
      'area': payload['areaHectares'],
      'grass_type': payload['grassType'],
      'status': payload['status'],
      'rest_days': _restDays(payload['lastUsedAt']),
      'last_used_at': payload['lastUsedAt'],
      'created_at': payload['createdAt'],
      'updated_at': payload['updatedAt'],
    });
  }

  Future<void> _pushAnimal(Map<String, Object?> payload) async {
    final userId = await _currentUserId();

    await _client.from('animals').upsert({
      'id': payload['id'],
      'user_id': userId,
      'code': payload['code'],
      'name': payload['name'],
      'type': payload['type'],
      'breed': payload['breed'],
      'sex': payload['sex'],
      'photo_path': payload['photoPath'],
      'birth_date': payload['birthDate'],
      'weight': payload['weight'],
      'paddock_id': payload['paddockId'],
      'notes': payload['notes'],
      'status': payload['status'],
      'created_at': payload['createdAt'],
      'updated_at': payload['updatedAt'],
    });
  }

  Future<void> _pushMovement(Map<String, Object?> payload) async {
    final userId = await _currentUserId();

    final date = payload['date'];

    await _client.from('animal_movements').upsert({
      'id': payload['id'],
      'user_id': userId,
      'animal_id': payload['animalId'],
      'from_paddock_id': payload['fromPaddockId'],
      'to_paddock_id': payload['toPaddockId'],
      'moved_at': date,
      'created_at': date,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _pushExpense(Map<String, Object?> payload) async {
    final userId = await _currentUserId();

    await _client.from('expenses').upsert({
      'id': payload['id'],
      'user_id': userId,
      'category': payload['category'],
      'amount': payload['amount'],
      'date': payload['date'],
      'note': payload['note'],
      'updated_at': payload['updatedAt'],
    });
  }

  int _restDays(Object? lastUsedAt) {
    if (lastUsedAt == null) return 0;

    final parsed = DateTime.tryParse(lastUsedAt.toString());
    if (parsed == null) return 0;

    return DateTime.now().difference(parsed).inDays;
  }
}
