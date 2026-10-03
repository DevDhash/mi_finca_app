part of 'app_database.dart';

const paddockPatchCollection = 'paddock_edit_commands';

extension PaddockPatchStore on AppDatabase {
  Future<List<PendingRecord>> paddockPatches(
    String owner, {
    String? entityId,
  }) async {
    await requireOwner(owner);
    final records = <PendingRecord>[];
    for (final p in await readRecords(paddockPatchCollection)) {
      if (SyncMetadata.owner(p) != owner ||
          (entityId != null && p['entityId'] != entityId)) {
        continue;
      }
      records.add(
        (await readRecord(paddockPatchCollection, p['id']! as String))!,
      );
    }
    records.sort(
      (a, b) =>
          (a.payload['order'] as int).compareTo(b.payload['order'] as int),
    );
    return records;
  }

  Future<String?> applyPaddockPatch(
    String id,
    String owner,
    PaddockPatch patch,
  ) => transaction(() async {
    await requireOwner(owner);
    if (patch.fields.isEmpty) return null;
    final current = await readRecord('paddocks', id, includeDeleted: true);
    if (current == null || current.ownerId != owner || current.isDeleted) {
      throw StateError('Potrero no disponible para editar.');
    }
    final pending = (await readPendingRecords()).any(
      (r) => r.collection == 'paddocks' && r.id == id,
    );
    final move = current.payload['_moveProjection'];
    final conflict = move != null && patch.operational;
    final order =
        int.parse(await readSetting('paddock_patch_order') ?? '0') + 1;
    await writeSetting('paddock_patch_order', order.toString());
    final operation = const Uuid().v4();
    final now = DateTime.now().toUtc();
    await putRecord(paddockPatchCollection, operation, {
      'id': operation,
      'entityId': id,
      'collection': 'paddocks',
      'kind': 'user_edit_patch',
      'baseRevision': current.revision,
      'fields': patch.localValues,
      'order': order,
      'createdAt': now.toIso8601String(),
      'state': conflict ? 'conflict' : 'pending',
      if (move != null) 'afterMove': (move as Map)['id'],
      if (conflict) 'error': 'OPERATIONAL_MOVE_CONFLICT',
    }, now);
    final command = (await readRecord(paddockPatchCollection, operation))!;
    if (conflict) {
      await replaceRecordIfUnchanged(command, command.payload, pending: false);
    }
    final projection = {...current.payload};
    // Freeze a pre-existing CREATE/legacy write before changing its UI projection.
    if (pending && !projection.containsKey('_basePaddockWrite')) {
      projection['_basePaddockWrite'] = {...current.payload};
    }
    if (!conflict) projection.addAll(_paddockOverlay(patch.localValues));
    projection['_sync'] = {
      ...SyncMetadata.read(current.payload),
      'revision': current.revision + 1,
    };
    await _writeRecord('paddocks', id, projection, now, pending: pending);
    return operation;
  });

  /// Future MOVE caller supplies its durable ID. Not used by legacy move flow.
  /// Pending full writes/patches must be resolved before this boundary: no guessing.
  Future<void> projectPaddockMove(
    String id,
    String owner,
    String movementId,
    PaddockPatch projection,
  ) => transaction(() async {
    await requireOwner(owner);
    if (movementId.isEmpty ||
        projection.fields.isEmpty ||
        projection.fields.keys.any((f) => !f.operational)) {
      throw ArgumentError('Invalid MOVE projection');
    }
    final current = await readRecord('paddocks', id, includeDeleted: true);
    if (current == null ||
        current.ownerId != owner ||
        current.isDeleted ||
        current.remotePresence != RemotePresence.confirmed ||
        current.payload['_moveProjection'] != null ||
        (await readPendingRecords()).any(
          (r) => r.collection == 'paddocks' && r.id == id,
        ) ||
        (await paddockPatches(
          owner,
          entityId: id,
        )).any((r) => r.payload['state'] != 'completed')) {
      throw StateError('Resolve paddock dependencies before MOVE projection');
    }
    await _writeRecord(
      'paddocks',
      id,
      {
        ...current.payload,
        ..._paddockOverlay(projection.localValues),
        '_moveProjection': {'id': movementId, 'fields': projection.localValues},
        '_sync': {
          ...SyncMetadata.read(current.payload),
          'revision': current.revision + 1,
        },
      },
      DateTime.now().toUtc(),
      pending: false,
    );
  });

  /// Only the future MOVE coordinator may call this after validated RPC success.
  /// Does not infer completion from missing commands or matching field values.
  Future<bool> completePaddockMoveProjection(
    PendingRecord expected,
    String movementId,
    Map<String, Object?> authoritative,
  ) => transaction(() async {
    final owner = expected.ownerId;
    if (owner == null) return false;
    await requireOwner(owner);
    final current = await readRecord(
      'paddocks',
      expected.id,
      includeDeleted: true,
    );
    if (expected.collection != 'paddocks' ||
        current == null ||
        current.isDeleted ||
        !SyncMetadata.sameOperation(current.payload, expected.payload) ||
        current.updatedAt != expected.updatedAt ||
        (current.payload['_moveProjection'] as Map?)?['id'] != movementId) {
      return false;
    }
    if (authoritative['id'] != expected.id ||
        authoritative['user_id'] != owner ||
        !authoritative.containsKey('deleted_at') ||
        authoritative['deleted_at'] != null ||
        authoritative.containsKey('_sync') ||
        authoritative.containsKey('_moveProjection')) {
      throw ArgumentError('Invalid authoritative paddock');
    }
    final projection = {
      ...authoritative,
      '_sync': SyncMetadata.read(current.payload),
    };
    for (final patch in await paddockPatches(owner, entityId: expected.id)) {
      if (patch.payload['state'] == 'pending') {
        projection.addAll(
          _paddockOverlay(
            Map<String, Object?>.from(patch.payload['fields'] as Map),
          ),
        );
      }
    }
    await _writeRecord(
      'paddocks',
      expected.id,
      projection,
      current.updatedAt,
      pending: false,
    );
    return true;
  });

  Map<String, Object?> _paddockOverlay(Map<String, Object?> fields) => {
    ...fields,
    if (fields.containsKey('pastureType')) 'grassType': fields['pastureType'],
    if (fields.containsKey('lastGrazingEndDate'))
      'lastUsedAt': fields['lastGrazingEndDate'],
  };

  Future<Map<String, Object?>> overlayPaddockIntents(
    String id,
    String owner,
    Map<String, Object?> remote,
  ) async {
    final result = {...remote};
    final local = await readRecord('paddocks', id, includeDeleted: true);
    final move = local?.payload['_moveProjection'];
    if (move is Map) {
      result.addAll(
        _paddockOverlay(Map<String, Object?>.from(move['fields'] as Map)),
      );
      result['_moveProjection'] = move;
    }
    for (final command in await paddockPatches(owner, entityId: id)) {
      if (command.payload['state'] == 'pending') {
        result.addAll(
          _paddockOverlay(
            Map<String, Object?>.from(command.payload['fields'] as Map),
          ),
        );
      }
    }
    return result;
  }

  Future<bool> patchReady(PendingRecord expected) => transaction(() async {
    if (expected.ownerId == null) return false;
    await requireOwner(expected.ownerId!);
    final current = await readRecord(paddockPatchCollection, expected.id);
    if (current == null ||
        !SyncMetadata.sameOperation(current.payload, expected.payload) ||
        current.payload['state'] != 'pending') {
      return false;
    }
    final parent = await readRecord(
      'paddocks',
      expected.payload['entityId']! as String,
      includeDeleted: true,
    );
    if (parent == null ||
        parent.ownerId != expected.ownerId ||
        parent.isDeleted ||
        parent.payload['_moveProjection'] != null ||
        parent.remotePresence != RemotePresence.confirmed) {
      return false;
    }
    if ((await readPendingRecords()).any(
      (r) => r.collection == 'paddocks' && r.id == parent.id,
    )) {
      return false;
    }
    return !(await paddockPatches(expected.ownerId!, entityId: parent.id)).any(
      (r) =>
          (r.payload['order'] as int) < (expected.payload['order'] as int) &&
          r.payload['state'] != 'completed',
    );
  });

  Future<bool> finishPaddockPatch(PendingRecord expected, {String? error}) =>
      transaction(() async {
        if (expected.ownerId == null ||
            expected.collection != paddockPatchCollection ||
            (expected.payload['state'] != 'pending' &&
                !(error != null && expected.payload['state'] == 'conflict'))) {
          return false;
        }
        await requireOwner(expected.ownerId!);
        return replaceRecordIfUnchanged(expected, {
          ...expected.payload,
          'state': error == null ? 'completed' : 'conflict',
          if (error != null) 'error': error,
        }, pending: false);
      });

  Future<void> conflictPaddockPatches(String id, String owner) async {
    for (final command in await paddockPatches(owner, entityId: id)) {
      if (command.payload['state'] != 'completed') {
        await finishPaddockPatch(command, error: 'SYNC_ENTITY_DELETED');
      }
    }
  }

  Future<bool> hasUnresolvedPaddockIntents() async {
    for (final p in await readRecords(paddockPatchCollection)) {
      if (p['state'] != 'completed') return true;
    }
    return (await readRecords(
      'paddocks',
      includeDeleted: true,
    )).any((p) => !SyncMetadata.isDeleted(p) && p['_moveProjection'] != null);
  }
}
