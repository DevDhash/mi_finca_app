import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_photo_upload.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_remote_payload.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_move_command.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_patch.dart';
import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_patch.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseSyncRemoteDataSource
    implements
        SyncRemoteDataSource,
        DeletionRemoteDataSource,
        PaddockPatchRemoteDataSource,
        AnimalMoveRemoteDataSource,
        AnimalPatchRemoteDataSource,
        PaddockReconciliationRemoteDataSource {
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
    // A concurrent late commit may be seen on the NEXT full pull
    // (no saved cursor).
    const pageSize = 500;
    var after = 0;
    final result = <RemoteTombstone>[];

    while (true) {
      _requireOwner(ownerId);

      final rows = await _client
          .from('sync_deletions')
          .select(
            'sequence, collection, entity_id, user_id, '
            'deleted_at, operation_id',
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

      // Do not assume a short page is complete:
      // a server cap may be lower.
      if (rows.isEmpty) {
        return result;
      }
    }
  }

  @override
  Future<String?> animalVersion(String id, String owner) async {
    _requireOwner(owner);

    final row = await _client
        .from('animals')
        .select('updated_at')
        .eq('id', id)
        .eq('user_id', owner)
        .isFilter('deleted_at', null)
        .maybeSingle();

    _requireOwner(owner);

    return row?['updated_at'] as String?;
  }

  @override
  Future<Map<String, Object?>> readAnimalMoveState(
    PendingRecord command,
  ) async {
    final move = AnimalMoveCommand.fromLocal(command.payload);
    _requireOwner(move.ownerId);
    final animal = await _client
        .from('animals')
        .select('id,user_id,paddock_id,deleted_at')
        .eq('id', move.animalId)
        .eq('user_id', move.ownerId)
        .maybeSingle();
    final paddocks = <Map<String, Object?>>[];
    for (final id in {
      move.fromPaddockId,
      move.toPaddockId,
    }.whereType<String>()) {
      final row = await _client
          .from('paddocks')
          .select(
            'id,user_id,status,grazing_start_date,planned_grazing_days,last_grazing_end_date,deleted_at',
          )
          .eq('id', id)
          .eq('user_id', move.ownerId)
          .maybeSingle();
      if (row != null) paddocks.add(row);
    }
    _requireOwner(move.ownerId);
    return {'animal': animal, 'paddocks': paddocks};
  }

  @override
  Future<Map<String, Object?>> pushAnimalMove(PendingRecord command) async {
    final owner = command.ownerId;

    if (owner == null || owner.isEmpty) {
      throw StateError('MOVE sin propietario persistido.');
    }

    if (command.collection != animalMoveCollection) {
      throw StateError('Invalid MOVE command collection');
    }

    if (command.payload['state'] != 'pending') {
      throw StateError('MOVE command is not pending');
    }

    _requireOwner(owner);

    final move = AnimalMoveCommand.fromLocal(command.payload);

    if (move.ownerId != owner || move.movementId != command.id) {
      throw StateError('Invalid MOVE command identity');
    }

    final result = await _client.rpc(
      'sync_move_animal',
      params: {
        'p_owner_id': move.ownerId,
        'p_animal_id': move.animalId,
        'p_movement_id': move.movementId,
        'p_from_paddock_id': move.fromPaddockId,
        'p_to_paddock_id': move.toPaddockId,
        'p_moved_at': move.movedAt.toUtc().toIso8601String(),
        'p_planned_grazing_days': move.plannedGrazingDays,
      },
    );

    // The HTTP request may have completed after the user/session changed.
    // Never consume its result under another account.
    _requireOwner(owner);

    if (result is! Map) {
      throw StateError('Invalid sync_move_animal response');
    }

    final response = Map<String, Object?>.from(result);

    // D1 returns the authoritative animal_movements row.
    // Validate its identity before treating the response as evidence.
    if (response['id'] != move.movementId ||
        response['user_id'] != owner ||
        response['animal_id'] != move.animalId ||
        response['from_paddock_id'] != move.fromPaddockId ||
        response['to_paddock_id'] != move.toPaddockId) {
      throw StateError('Invalid sync_move_animal response identity');
    }

    final remoteMovedAt = response['moved_at'];

    if (remoteMovedAt is! String) {
      throw StateError('Invalid sync_move_animal movement date');
    }

    DateTime parsedMovedAt;

    try {
      parsedMovedAt = DateTime.parse(remoteMovedAt).toUtc();
    } on FormatException {
      throw StateError('Invalid sync_move_animal movement date');
    }

    if (!parsedMovedAt.isAtSameMomentAs(move.movedAt.toUtc())) {
      throw StateError('Invalid sync_move_animal movement identity');
    }

    return response;
  }

  @override
  Future<void> pushAnimalPatch(PendingRecord command) async {
    final owner = command.ownerId;
    final version = command.payload['remoteBaseVersion'];

    if (owner == null ||
        version is! String ||
        command.collection != animalPatchCollection) {
      throw StateError('Invalid patch');
    }

    _requireOwner(owner);

    final patch = AnimalPatch.fromLocal(
      Map<String, Object?>.from(command.payload['fields'] as Map),
    );

    final rows = await _client
        .from('animals')
        .update(patch.remoteValues)
        .eq('id', command.payload['entityId']! as String)
        .eq('user_id', owner)
        .eq('updated_at', version)
        .isFilter('deleted_at', null)
        .select('id,user_id');

    _requireOwner(owner);

    if (rows.length != 1 ||
        rows.single['id'] != command.payload['entityId'] ||
        rows.single['user_id'] != owner) {
      throw const PostgrestException(
        message: 'PATCH_VERSION_CONFLICT',
        code: 'P0001',
      );
    }
  }

  @override
  Future<Map<String, Object?>?> readActivePaddock(
    String id,
    String owner,
  ) async {
    _requireOwner(owner);
    final row = await _client
        .from('paddocks')
        .select()
        .eq('id', id)
        .eq('user_id', owner)
        .isFilter('deleted_at', null)
        .maybeSingle();
    _requireOwner(owner);
    if (row == null) return null;
    return {
      ...row,
      'areaHectares': row['area'],
      'pastureType': row['pasture_type'],
      'requiredRestDays': row['required_rest_days'],
      'rotationOrder': row['rotation_order'],
      'grazingStartDate': row['grazing_start_date'],
      'plannedGrazingDays': row['planned_grazing_days'],
      'lastGrazingEndDate': row['last_grazing_end_date'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
    };
  }

  @override
  Future<String?> paddockVersion(String id, String owner) async {
    _requireOwner(owner);

    final row = await _client
        .from('paddocks')
        .select('updated_at')
        .eq('id', id)
        .eq('user_id', owner)
        .isFilter('deleted_at', null)
        .maybeSingle();

    _requireOwner(owner);

    return row?['updated_at'] as String?;
  }

  @override
  Future<void> pushPaddockPatch(PendingRecord command) async {
    final owner = command.ownerId;
    final version = command.payload['remoteBaseVersion'];

    if (owner == null ||
        version is! String ||
        command.collection != paddockPatchCollectionName) {
      throw StateError('Invalid patch');
    }

    _requireOwner(owner);

    final patch = PaddockPatch.fromLocal(
      Map<String, Object?>.from(command.payload['fields'] as Map),
    );

    final rows = await _client
        .from('paddocks')
        .update(patch.remoteValues)
        .eq('id', command.payload['entityId']! as String)
        .eq('user_id', owner)
        .eq('updated_at', version)
        .isFilter('deleted_at', null)
        .select('id,user_id');

    _requireOwner(owner);

    if (rows.length != 1 ||
        rows.single['id'] != command.payload['entityId'] ||
        rows.single['user_id'] != owner) {
      throw const PostgrestException(
        message: 'PATCH_VERSION_CONFLICT',
        code: 'P0001',
      );
    }
  }

  static const paddockPatchCollectionName = 'paddock_edit_commands';

  @override
  Future<void> pushRecord(PendingRecord record) async {
    if (record.isDeleted || record.operation != 'upsert') {
      throw StateError('DELETE debe usar softDelete.');
    }

    if ((record.collection == 'paddocks' ||
            (record.collection == 'animals' &&
                SyncMetadata.read(record.payload)['writeKind'] != 'photo')) &&
        record.payload['_moveProjection'] != null) {
      throw StateError('MOVE projection requires atomic command publication.');
    }

    final owner = record.ownerId;

    if (owner == null) {
      throw StateError('Propietario legacy no verificado.');
    }

    _requireOwner(owner);

    switch (record.collection) {
      case 'farms':
        return _pushFarm(record.payload, owner);

      case 'paddocks':
        return _pushPaddock(
          record.payload['_basePaddockWrite'] is Map
              ? Map<String, Object?>.from(
                  record.payload['_basePaddockWrite'] as Map,
                )
              : record.payload,
          owner,
        );

      case 'animals':
        return _pushAnimal(record.payload, owner);

      case 'movements':
        return _pushMovement(record.payload, owner);

      case 'expenses':
        return _pushExpense(record.payload, owner);

      default:
        throw UnsupportedError(
          'Colección no soportada para sync: '
          '${record.collection}',
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

    final kind = SyncMetadata.read(payload)['writeKind'];

    if (kind == 'create') {
      final source = payload['_baseAnimalCreate'] is Map
          ? Map<String, Object?>.from(payload['_baseAnimalCreate'] as Map)
          : payload;

      // INSERT ON CONFLICT DO NOTHING:
      // retries must never restore location.
      await _client
          .from('animals')
          .upsert(
            AnimalRemotePayload.fromLocal(source, userId),
            onConflict: 'id',
            ignoreDuplicates: true,
          );

      _requireOwner(userId);

      final existing = await _client
          .from('animals')
          .select('id')
          .eq('id', payload['id']! as String)
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .maybeSingle();

      if (existing == null) {
        throw StateError('CREATE target unavailable');
      }

      if (job == null) {
        return;
      }
    } else if (kind != 'photo') {
      throw StateError('LEGACY_LOCATION_AMBIGUOUS');
    }

    final path = AnimalRemotePayload.validatedPhotoPath(
      payload['remotePhotoPath'],
      userId,
      payload['id']! as String,
    );

    if (path == null) {
      throw StateError('Photo reference unavailable');
    }

    final rows = await _client
        .from('animals')
        .update({'remote_photo_path': path})
        .eq('id', payload['id']! as String)
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .select('id');

    _requireOwner(userId);

    if (rows.length != 1) {
      throw StateError('Photo target unavailable');
    }
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
