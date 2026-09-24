import 'package:mi_finca_app/features/animals/data/models/animal_photo_upload.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_remote_payload.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseSyncRemoteDataSource implements SyncRemoteDataSource {
  const SupabaseSyncRemoteDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<void> pushRecord(PendingRecord record) async {
    switch (record.collection) {
      case 'farms':
        return _pushFarm(record.payload);
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

  Future<void> _pushFarm(Map<String, Object?> payload) async {
    final userId = await _currentUserId();

    await _client.from('farms').upsert({
      'id': payload['id'],
      'user_id': userId,
      'name': payload['name'],
      'location': payload['location'],
    });
  }

  Future<void> _pushPaddock(Map<String, Object?> payload) async {
    final userId = await _currentUserId();

    await _client.from('paddocks').upsert({
      'id': payload['id'],
      'user_id': userId,
      'name': payload['name'],
      'area': payload['areaHectares'],
      'pasture_type': payload['pastureType'] ?? payload['grassType'],
      'required_rest_days': payload['requiredRestDays'],
      'rotation_order': payload['rotationOrder'],
      'grazing_start_date': payload['grazingStartDate'],
      'planned_grazing_days': payload['plannedGrazingDays'],
      'status': payload['status'],
      'last_grazing_end_date':
          payload['lastGrazingEndDate'] ?? payload['lastUsedAt'],
      'created_at': payload['createdAt'],
      'updated_at': payload['updatedAt'],
    });
  }

  Future<void> _pushAnimal(Map<String, Object?> payload) async {
    final userId = await _currentUserId();
    final job = AnimalPhotoUpload.read(payload);
    if (job != null && job['ownerId'] != userId) {
      throw const AuthException('La foto pertenece a otra sesión.');
    }

    await _client
        .from('animals')
        .upsert(AnimalRemotePayload.fromLocal(payload, userId));
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
}
