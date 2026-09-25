import 'package:mi_finca_app/features/animals/data/models/animal_photo_upload.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_remote_payload.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseSyncRemoteDataSource
    implements SyncRemoteDataSource, DeletionRemoteDataSource {
  const SupabaseSyncRemoteDataSource(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  static String tableFor(String collection) {
    if (!SyncMetadata.collections.contains(collection)) {
      throw ArgumentError.value(collection, 'collection');
    }
    return collection == 'movements' ? 'animal_movements' : collection;
  }

  void _requireOwner(String owner) {
    if (currentUserId != owner || _client.auth.currentSession == null) {
      throw const AuthException('La operación pertenece a otra sesión.');
    }
  }

  @override
  Future<bool> verifyLegacyOwner(PendingRecord record, String ownerId) async {
    _requireOwner(ownerId);
    final row = await _client
        .from(tableFor(record.collection))
        .select('id, user_id')
        .eq('id', record.id)
        .eq('user_id', ownerId)
        .maybeSingle();
    _requireOwner(ownerId);
    return row?['user_id'] == ownerId;
  }

  @override
  Future<RemoteTombstone> softDelete(PendingRecord record) async {
    final owner = record.ownerId;
    if (!record.isDeleted ||
        record.operation != 'delete' ||
        owner == null ||
        record.operationId == null) {
      throw StateError('DELETE sin intención o propietario persistido.');
    }
    tableFor(record.collection);
    _requireOwner(owner);
    final result = await _client.rpc(
      'sync_soft_delete',
      params: {
        'p_collection': record.collection,
        'p_entity_id': record.id,
        'p_owner_id': owner,
        'p_operation_id': record.operationId,
      },
    );
    _requireOwner(owner);
    final remote = RemoteTombstone.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
    if (remote.ownerId != owner ||
        remote.id != record.id ||
        remote.collection != record.collection) {
      throw StateError('Confirmación remota inválida.');
    }
    return remote;
  }

  @override
  Future<List<RemoteTombstone>> fetchTombstones(String ownerId) async {
    _requireOwner(ownerId);
    // Immutable increasing sequence, keyset pagination; never infer absence.
    // A concurrent late commit may be seen on the NEXT full pull (no saved cursor).
    const pageSize = 500;
    var after = 0;
    final result = <RemoteTombstone>[];
    while (true) {
      _requireOwner(ownerId);
      final rows = await _client
          .from('sync_deletions')
          .select(
            'sequence, collection, entity_id, user_id, deleted_at, operation_id',
          )
          .eq('user_id', ownerId)
          .gt('sequence', after)
          .order('sequence')
          .limit(pageSize);
      _requireOwner(ownerId);
      for (final row in rows) {
        final item = RemoteTombstone.fromJson(row);
        if (item.ownerId != ownerId) {
          throw StateError('Propietario remoto inválido.');
        }
        result.add(item);
        after = (row['sequence'] as num).toInt();
      }
      // Do not assume a short page is complete: a server cap may be lower.
      if (rows.isEmpty) return result;
    }
  }

  @override
  Future<void> pushRecord(PendingRecord record) async {
    if (record.isDeleted || record.operation != 'upsert') {
      throw StateError('DELETE debe usar softDelete.');
    }
    final owner = record.ownerId;
    if (owner == null) throw StateError('Propietario legacy no verificado.');
    _requireOwner(owner);
    switch (record.collection) {
      case 'farms':
        return _pushFarm(record.payload, owner);
      case 'paddocks':
        return _pushPaddock(record.payload, owner);
      case 'animals':
        return _pushAnimal(record.payload, owner);
      case 'movements':
        return _pushMovement(record.payload, owner);
      case 'expenses':
        return _pushExpense(record.payload, owner);
      default:
        throw UnsupportedError(
          'Colección no soportada para sync: ${record.collection}',
        );
    }
  }

  Future<void> _pushFarm(Map<String, Object?> payload, String userId) async {
    _requireOwner(userId);

    await _client.from('farms').upsert({
      'id': payload['id'],
      'user_id': userId,
      'name': payload['name'],
      'location': payload['location'],
    });
  }

  Future<void> _pushPaddock(Map<String, Object?> payload, String userId) async {
    _requireOwner(userId);

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

  Future<void> _pushAnimal(Map<String, Object?> payload, String userId) async {
    _requireOwner(userId);
    final job = AnimalPhotoUpload.read(payload);
    if (job != null && job['ownerId'] != userId) {
      throw const AuthException('La foto pertenece a otra sesión.');
    }

    await _client
        .from('animals')
        .upsert(AnimalRemotePayload.fromLocal(payload, userId));
  }

  Future<void> _pushMovement(
    Map<String, Object?> payload,
    String userId,
  ) async {
    _requireOwner(userId);

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

  Future<void> _pushExpense(Map<String, Object?> payload, String userId) async {
    _requireOwner(userId);

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
