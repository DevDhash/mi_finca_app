part of 'app_database.dart';

const animalPatchCollection = 'animal_edit_commands';

/// Uses the A2 records/outbox/CAS protocol with animal-specific field ownership.
extension AnimalPatchStore on AppDatabase {
  Future<List<PendingRecord>> animalPatches(
    String owner, {
    String? entityId,
  }) async {
    await requireOwner(owner);
    final result = <PendingRecord>[];
    for (final p in await readRecords(animalPatchCollection)) {
      if (SyncMetadata.owner(p) == owner &&
          (entityId == null || p['entityId'] == entityId)) {
        result.add(
          (await readRecord(animalPatchCollection, p['id']! as String))!,
        );
      }
    }
    result.sort(
      (a, b) =>
          (a.payload['order'] as int).compareTo(b.payload['order'] as int),
    );
    return result;
  }

  Future<String?> applyAnimalPatch(
    String id,
    String owner,
    AnimalPatch patch,
  ) => transaction(() async {
    await requireOwner(owner);
    if (patch.fields.isEmpty) return null;
    final current = await readRecord('animals', id, includeDeleted: true);
    if (current == null ||
        current.ownerId != owner ||
        current.isDeleted ||
        current.payload['_animalConflict'] != null) {
      throw StateError('Animal unavailable for edit');
    }
    final pending = (await readPendingRecords()).any(
      (r) => r.collection == 'animals' && r.id == id,
    );
    if (pending &&
        ![
          'create',
          'photo',
        ].contains(SyncMetadata.read(current.payload)['writeKind'])) {
      throw StateError('LEGACY_LOCATION_AMBIGUOUS');
    }
    final order = int.parse(await readSetting('animal_patch_order') ?? '0') + 1;
    await writeSetting('animal_patch_order', '$order');
    final operation = const Uuid().v4();
    final now = DateTime.now().toUtc();
    await putRecord(animalPatchCollection, operation, {
      'id': operation,
      'entityId': id,
      'collection': 'animals',
      'kind': 'user_edit_patch',
      'baseRevision': current.revision,
      'fields': patch.localValues,
      'order': order,
      'state': 'pending',
      'createdAt': now.toIso8601String(),
    }, now);
    final projection = {...current.payload};
    if (pending &&
        SyncMetadata.read(projection)['writeKind'] == 'create' &&
        !projection.containsKey('_baseAnimalCreate')) {
      projection['_baseAnimalCreate'] = {...current.payload};
    }
    projection.addAll(patch.localValues);
    projection['_sync'] = {
      ...SyncMetadata.read(current.payload),
      'revision': current.revision + 1,
    };
    await _writeRecord('animals', id, projection, now, pending: pending);
    return operation;
  });

  Future<void> projectAnimalMove(
    String id,
    String owner,
    String movementId,
    String? destination,
  ) => transaction(() async {
    await requireOwner(owner);
    final current = await readRecord('animals', id, includeDeleted: true);
    if (movementId.isEmpty ||
        current == null ||
        current.ownerId != owner ||
        current.isDeleted ||
        current.remotePresence != RemotePresence.confirmed ||
        current.payload['_moveProjection'] != null ||
        current.payload['_animalConflict'] != null ||
        (await readPendingRecords()).any(
          (r) => r.collection == 'animals' && r.id == id,
        )) {
      throw StateError('Resolve animal dependencies before MOVE projection');
    }
    await _writeRecord(
      'animals',
      id,
      {
        ...current.payload,
        'paddockId': destination,
        '_moveProjection': {
          'id': movementId,
          'fromPaddockId': current.payload['paddockId'],
          'paddockId': destination,
        },
        '_sync': {
          ...SyncMetadata.read(current.payload),
          'revision': current.revision + 1,
        },
      },
      DateTime.now().toUtc(),
      pending: false,
    );
  });

  Future<Map<String, Object?>> overlayAnimalIntents(
    String id,
    String owner,
    Map<String, Object?> remote,
  ) async {
    final current = await readRecord('animals', id, includeDeleted: true);
    final result = {...remote};
    if (current?.ownerId != null && current!.ownerId != owner) {
      throw StateError('Owner mismatch');
    }
    if (current?.payload['_animalConflict'] != null) {
      return {...current!.payload};
    }
    final move = current?.payload['_moveProjection'];
    if (move is Map) {
      result['_moveProjection'] = move;
      result['paddockId'] = move['paddockId'];
    }
    for (final command in await animalPatches(owner, entityId: id)) {
      if (command.payload['state'] == 'pending') {
        result.addAll(
          AnimalPatch.fromLocal(
            Map<String, Object?>.from(command.payload['fields'] as Map),
          ).localValues,
        );
      }
    }
    return result;
  }

  Future<bool> animalPatchReady(PendingRecord expected) => transaction(
    () async {
      final owner = expected.ownerId;
      if (owner == null || expected.collection != animalPatchCollection) {
        return false;
      }
      await requireOwner(owner);
      final current = await readRecord(animalPatchCollection, expected.id);
      if (current == null ||
          current.payload['state'] != 'pending' ||
          !SyncMetadata.sameOperation(current.payload, expected.payload)) {
        return false;
      }
      final parent = await readRecord(
        'animals',
        expected.payload['entityId']! as String,
        includeDeleted: true,
      );
      if (parent == null ||
          parent.ownerId != owner ||
          parent.isDeleted ||
          parent.payload['_animalConflict'] != null ||
          parent.remotePresence != RemotePresence.confirmed) {
        return false;
      }
      if ((await readPendingRecords()).any(
        (r) =>
            r.collection == 'animals' &&
            r.id == parent.id &&
            SyncMetadata.read(r.payload)['writeKind'] == 'create',
      )) {
        return false;
      }
      return !(await animalPatches(owner, entityId: parent.id)).any(
        (r) =>
            (r.payload['order'] as int) < (expected.payload['order'] as int) &&
            r.payload['state'] != 'completed',
      );
    },
  );

  Future<bool> finishAnimalPatch(
    PendingRecord expected, {
    String? error,
  }) => transaction(() async {
    if (expected.ownerId == null ||
        expected.collection != animalPatchCollection ||
        (expected.payload['state'] != 'pending' &&
            !(error != null && expected.payload['state'] == 'conflict'))) {
      return false;
    }
    await requireOwner(expected.ownerId!);
    final parent = await readRecord(
      'animals',
      expected.payload['entityId']! as String,
      includeDeleted: true,
    );
    final changed = await replaceRecordIfUnchanged(expected, {
      ...expected.payload,
      'state': error == null && parent?.isDeleted == false
          ? 'completed'
          : 'conflict',
      if (error != null || parent?.isDeleted != false)
        'error': error ?? 'SYNC_ENTITY_DELETED',
    }, pending: false);
    // Invalidate GET snapshots started before this ACK without replaying fields.
    if (changed && parent != null && !parent.isDeleted) {
      final latest = await readRecord(
        'animals',
        parent.id,
        includeDeleted: true,
      );
      if (latest != null && !latest.isDeleted) {
        final pending = (await readPendingRecords()).any(
          (r) => r.collection == 'animals' && r.id == parent.id,
        );
        await _writeRecord(
          'animals',
          parent.id,
          {
            ...latest.payload,
            '_sync': {
              ...SyncMetadata.read(latest.payload),
              'revision': latest.revision + 1,
            },
          },
          latest.updatedAt,
          pending: pending,
        );
      }
    }
    return changed;
  });

  Future<void> conflictAnimalPatches(String id, String owner) async {
    for (final command in await animalPatches(owner, entityId: id)) {
      if (command.payload['state'] != 'completed') {
        await finishAnimalPatch(command, error: 'SYNC_ENTITY_DELETED');
      }
    }
  }

  Future<bool> quarantineLegacyAnimal(PendingRecord expected) async {
    if (expected.collection != 'animals' ||
        expected.isDeleted ||
        [
          'create',
          'photo',
        ].contains(SyncMetadata.read(expected.payload)['writeKind'])) {
      return false;
    }
    if (expected.ownerId != null) await requireOwner(expected.ownerId!);
    return replaceRecordIfUnchanged(expected, {
      ...expected.payload,
      '_animalConflict': 'LEGACY_LOCATION_AMBIGUOUS',
      '_legacyAnimalPayload': expected.payload,
    }, pending: false);
  }

  Future<bool> hasUnresolvedAnimalIntents() async {
    if ((await readRecords(
      animalPatchCollection,
    )).any((p) => p['state'] != 'completed')) {
      return true;
    }
    return (await readRecords('animals', includeDeleted: true)).any(
      (p) =>
          p['_animalConflict'] != null ||
          (!SyncMetadata.isDeleted(p) && p['_moveProjection'] != null),
    );
  }
}
