part of 'app_database.dart';

const animalMoveCollection = 'animal_move_commands';

extension AnimalMoveStore on AppDatabase {
  Future<List<PendingRecord>> animalMoveCommands(
    String owner, {
    String? animalId,
  }) async {
    await requireOwner(owner);

    final result = <PendingRecord>[];

    for (final payload in await readRecords(
      animalMoveCollection,
      includeDeleted: true,
    )) {
      if (SyncMetadata.owner(payload) != owner ||
          (animalId != null && payload['animalId'] != animalId)) {
        continue;
      }

      final id = payload['movementId'];
      if (id is! String) continue;

      final record = await readRecord(
        animalMoveCollection,
        id,
        includeDeleted: true,
      );

      if (record != null) {
        result.add(record);
      }
    }

    result.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

    return result;
  }

  Future<PendingRecord> createAnimalMove({
    required AnimalMoveCommand command,
    required Map<String, Object?> movementPayload,
  }) => transaction(() async {
    _requireWritableSession();
    await requireOwner(command.ownerId);

    if (command.movementId.isEmpty ||
        command.animalId.isEmpty ||
        command.toPaddockId.isEmpty ||
        command.fromPaddockId == command.toPaddockId ||
        (command.plannedGrazingDays != null &&
            command.plannedGrazingDays! <= 0)) {
      throw ArgumentError('Invalid MOVE command');
    }

    final existingCommand = await readRecord(
      animalMoveCollection,
      command.movementId,
      includeDeleted: true,
    );

    if (existingCommand != null) {
      final existing = AnimalMoveCommand.fromLocal(existingCommand.payload);

      final same =
          existing.ownerId == command.ownerId &&
          existing.animalId == command.animalId &&
          existing.fromPaddockId == command.fromPaddockId &&
          existing.toPaddockId == command.toPaddockId &&
          existing.movedAt.toUtc() == command.movedAt.toUtc() &&
          existing.plannedGrazingDays == command.plannedGrazingDays;

      if (!same) {
        throw StateError('MOVE_ID_CONFLICT');
      }

      return existingCommand;
    }

    if ((await animalMoveCommands(
      command.ownerId,
      animalId: command.animalId,
    )).any((r) => r.payload['state'] != 'completed')) {
      throw StateError('Resolve previous MOVE before creating another');
    }
    final animal = await readRecord(
      'animals',
      command.animalId,
      includeDeleted: true,
    );

    if (animal == null ||
        animal.ownerId != command.ownerId ||
        animal.isDeleted ||
        animal.remotePresence != RemotePresence.confirmed ||
        animal.payload['_animalConflict'] != null ||
        animal.payload['_moveProjection'] != null ||
        animal.payload['paddockId'] != command.fromPaddockId) {
      throw StateError('El animal ya no está disponible para este movimiento.');
    }

    if ((await readPendingRecords()).any(
      (record) =>
          record.collection == 'animals' && record.id == command.animalId,
    )) {
      throw StateError('Sincroniza los cambios del animal antes de moverlo.');
    }

    if ((await animalPatches(
      command.ownerId,
      entityId: command.animalId,
    )).any((record) => record.payload['state'] != 'completed')) {
      throw StateError(
        'Resuelve los cambios pendientes del animal antes de moverlo.',
      );
    }

    final destination = await readRecord(
      'paddocks',
      command.toPaddockId,
      includeDeleted: true,
    );

    if (destination == null ||
        destination.ownerId != command.ownerId ||
        destination.isDeleted ||
        destination.remotePresence != RemotePresence.confirmed ||
        destination.payload['_moveProjection'] != null) {
      throw StateError('El potrero destino no está disponible.');
    }

    if (command.fromPaddockId != null) {
      final source = await readRecord(
        'paddocks',
        command.fromPaddockId!,
        includeDeleted: true,
      );

      if (source == null ||
          source.ownerId != command.ownerId ||
          source.isDeleted ||
          source.remotePresence != RemotePresence.confirmed ||
          source.payload['_moveProjection'] != null) {
        throw StateError('El potrero origen no está disponible.');
      }
    }

    final affected = {
      command.fromPaddockId,
      command.toPaddockId,
    }.whereType<String>().toSet();
    if ((await readPendingRecords()).any(
      (r) => r.collection == 'paddocks' && affected.contains(r.id),
    )) {
      throw StateError('Synchronize paddock writes before MOVE');
    }
    for (final id in affected) {
      for (final patch in await paddockPatches(command.ownerId, entityId: id)) {
        if (patch.payload['state'] != 'completed' &&
            PaddockPatch.fromLocal(
              Map<String, Object?>.from(patch.payload['fields'] as Map),
            ).operational) {
          throw StateError('Resolve operational paddock edits before MOVE');
        }
      }
    }

    final now = DateTime.now().toUtc();

    // The command is the ONLY remote outbox entry for a D2 MOVE.
    //
    // Do not use verifiedRemoteOwner here. The command has not been
    // accepted by sync_move_animal yet.
    await putRecord(
      animalMoveCollection,
      command.movementId,
      command.toLocal(),
      now,
      pending: true,
    );

    // Optimistic animal projection. It is deliberately NOT an independent
    // remote write. Publication belongs exclusively to sync_move_animal().
    await projectAnimalMove(
      command.animalId,
      command.ownerId,
      command.movementId,
      command.toPaddockId,
    );

    // Local history is visible immediately but is NOT a generic outbox
    // entry and must NOT claim remote existence before the RPC succeeds.
    final existingMovement = await readRecord(
      'movements',
      command.movementId,
      includeDeleted: true,
    );

    if (existingMovement != null) {
      throw StateError('MOVE_ID_CONFLICT');
    }

    final movementMeta = {
      ...SyncMetadata.operation(
        ownerId: command.ownerId,
        operation: 'move_projection',
        revision: 1,
        requestedAt: now,
      ),
      'ownership': 'verified',
      'remotePresence': SyncMetadata.presenceValue(RemotePresence.localOnly),
      'movementId': command.movementId,
    };

    await _writeRecord(
      'movements',
      command.movementId,
      {...movementPayload, SyncMetadata.key: movementMeta},
      command.movedAt,
      pending: false,
    );

    final created = await readRecord(
      animalMoveCollection,
      command.movementId,
      includeDeleted: true,
    );

    if (created == null) {
      throw StateError('No se pudo persistir MOVE');
    }

    return created;
  });

  /// Reconciles a MOVE only after sync_move_animal returned positive evidence
  /// and the caller read the authoritative animal/paddock state afterwards.
  ///
  /// This method deliberately does NOT complete the durable MOVE command.
  /// The caller must complete it only after this reconciliation succeeds.
  Future<bool> reconcileAnimalMoveSuccess(
    PendingRecord expected, {
    required Map<String, Object?> movement,
    required Map<String, Object?> state,
  }) => transaction(() async {
    if (expected.collection != animalMoveCollection ||
        expected.ownerId == null ||
        expected.payload['state'] != 'pending') {
      return false;
    }

    final owner = expected.ownerId!;
    await requireOwner(owner);

    final command = AnimalMoveCommand.fromLocal(expected.payload);

    final currentCommand = await readRecord(
      animalMoveCollection,
      expected.id,
      includeDeleted: true,
    );

    if (currentCommand == null ||
        currentCommand.payload['state'] != 'pending' ||
        !SyncMetadata.sameOperation(currentCommand.payload, expected.payload)) {
      return false;
    }

    // The RPC response is positive evidence for this exact movement.
    if (movement['id'] != command.movementId ||
        movement['user_id'] != owner ||
        movement['animal_id'] != command.animalId ||
        movement['from_paddock_id'] != command.fromPaddockId ||
        movement['to_paddock_id'] != command.toPaddockId) {
      throw StateError('Invalid authoritative MOVE');
    }

    final remoteMovedAt = movement['moved_at'];

    if (remoteMovedAt is! String) {
      throw StateError('Invalid authoritative MOVE date');
    }

    DateTime parsedMovedAt;

    try {
      parsedMovedAt = DateTime.parse(remoteMovedAt).toUtc();
    } on FormatException {
      throw StateError('Invalid authoritative MOVE date');
    }

    if (!parsedMovedAt.isAtSameMomentAs(command.movedAt.toUtc())) {
      throw StateError('Invalid authoritative MOVE date');
    }

    final remoteAnimalRaw = state['animal'];
    final remotePaddocksRaw = state['paddocks'];

    if ((remoteAnimalRaw != null && remoteAnimalRaw is! Map) ||
        remotePaddocksRaw is! List) {
      throw StateError('Invalid authoritative MOVE state');
    }

    final remoteAnimal = remoteAnimalRaw == null
        ? null
        : Map<String, Object?>.from(remoteAnimalRaw as Map);

    if (remoteAnimal != null &&
        (remoteAnimal['id'] != command.animalId ||
            remoteAnimal['user_id'] != owner ||
            !remoteAnimal.containsKey('deleted_at') ||
            !remoteAnimal.containsKey('paddock_id'))) {
      throw StateError('Invalid authoritative MOVE state');
    }

    // A later DELETE wins. MOVE reconciliation must never resurrect it.

    final localAnimal = await readRecord(
      'animals',
      command.animalId,
      includeDeleted: true,
    );

    if (localAnimal == null || localAnimal.ownerId != owner) {
      return false;
    }

    if (!localAnimal.isDeleted) {
      final projection = localAnimal.payload['_moveProjection'];

      final history = await readRecord(
        'movements',
        command.movementId,
        includeDeleted: true,
      );
      final savedReceipt = history?.payload['_moveReceipt'];
      DateTime? savedMovedAt;
      if (savedReceipt is Map && savedReceipt['moved_at'] is String) {
        try {
          savedMovedAt = DateTime.parse(
            savedReceipt['moved_at'] as String,
          ).toUtc();
        } on FormatException {
          // Invalid stored evidence cannot authorize crash recovery.
        }
      }
      final reconciledBefore =
          history?.ownerId == owner &&
          history?.remotePresence == RemotePresence.confirmed &&
          savedReceipt is Map &&
          [
            'id',
            'user_id',
            'animal_id',
            'from_paddock_id',
            'to_paddock_id',
          ].every((key) => savedReceipt[key] == movement[key]) &&
          savedMovedAt != null &&
          savedMovedAt.isAtSameMomentAs(parsedMovedAt);
      if ((projection != null &&
              (projection is! Map || projection['id'] != command.movementId)) ||
          (projection == null && !reconciledBefore)) {
        return false;
      }
      if (remoteAnimal == null || remoteAnimal['deleted_at'] != null) {
        return false;
      }

      final nextAnimal = {...localAnimal.payload};

      // The server owns the final location after the atomic MOVE.
      nextAnimal['paddockId'] = remoteAnimal['paddock_id'];

      // Remove only the projection belonging to this MOVE.
      nextAnimal.remove('_moveProjection');

      nextAnimal[SyncMetadata.key] = {
        ...SyncMetadata.read(localAnimal.payload),
        'remotePresence': SyncMetadata.presenceValue(RemotePresence.confirmed),
        'revision': localAnimal.revision + 1,
      };

      await _writeRecord(
        'animals',
        localAnimal.id,
        nextAnimal,
        localAnimal.updatedAt,
        pending: (await readPendingRecords()).any(
          (r) => r.collection == 'animals' && r.id == localAnimal.id,
        ),
      );
    }

    // Confirm the provisional local history using the RPC response.
    final localMovement = await readRecord(
      'movements',
      command.movementId,
      includeDeleted: true,
    );

    if (localMovement == null ||
        localMovement.ownerId != owner ||
        localMovement.payload['animalId'] != command.animalId ||
        localMovement.payload['fromPaddockId'] != command.fromPaddockId ||
        localMovement.payload['toPaddockId'] != command.toPaddockId) {
      throw StateError('Invalid local MOVE projection');
    }

    final localMovementDate = localMovement.payload['date'];

    if (localMovementDate is! String) {
      throw StateError('Invalid local MOVE date');
    }

    DateTime parsedLocalMovementDate;

    try {
      parsedLocalMovementDate = DateTime.parse(localMovementDate).toUtc();
    } on FormatException {
      throw StateError('Invalid local MOVE date');
    }

    if (!parsedLocalMovementDate.isAtSameMomentAs(command.movedAt.toUtc())) {
      throw StateError('Invalid local MOVE identity');
    }

    await _writeRecord(
      'movements',
      command.movementId,
      {...localMovement.payload, '_moveReceipt': movement},
      localMovement.updatedAt,
      pending: false,
    );
    await _markRemoteConfirmedInTransaction(
      'movements',
      command.movementId,
      owner,
    );

    // D1 owns these operational paddock fields.
    // Descriptive fields remain untouched locally.
    for (final raw in remotePaddocksRaw) {
      if (raw is! Map) {
        throw StateError('Invalid authoritative paddock state');
      }

      final remote = Map<String, Object?>.from(raw);
      final id = remote['id'];

      if (id is! String ||
          remote['user_id'] != owner ||
          (id != command.fromPaddockId && id != command.toPaddockId)) {
        throw StateError('Invalid authoritative paddock');
      }

      if (!remote.containsKey('deleted_at')) {
        throw StateError('Incomplete paddock evidence');
      }
      if (remote['deleted_at'] != null) continue;
      final local = await readRecord('paddocks', id, includeDeleted: true);

      // Local terminal state wins over a MOVE snapshot.
      if (local == null || local.ownerId != owner || local.isDeleted) {
        continue;
      }

      var next = <String, Object?>{
        ...local.payload,
        'status': remote['status'],
        'grazingStartDate': remote['grazing_start_date'],
        'plannedGrazingDays': remote['planned_grazing_days'],
        'lastGrazingEndDate': remote['last_grazing_end_date'],
        // Legacy local alias still used by some existing paths.
        'lastUsedAt': remote['last_grazing_end_date'],
      };

      // Preserve independent A2 patch projections.
      next = await overlayPaddockIntents(id, owner, next);

      next[SyncMetadata.key] = {
        ...SyncMetadata.read(local.payload),
        'remotePresence': SyncMetadata.presenceValue(RemotePresence.confirmed),
        'revision': local.revision + 1,
      };

      final localPending = (await readPendingRecords()).any(
        (record) => record.collection == 'paddocks' && record.id == id,
      );

      await _writeRecord(
        'paddocks',
        id,
        next,
        local.updatedAt,
        pending: localPending,
      );
    }

    return true;
  });

  Future<bool> completeAnimalMoveCommand(PendingRecord expected) =>
      transaction(() async {
        if (expected.collection != animalMoveCollection ||
            expected.ownerId == null) {
          return false;
        }

        await requireOwner(expected.ownerId!);

        final current = await readRecord(
          animalMoveCollection,
          expected.id,
          includeDeleted: true,
        );

        if (current == null ||
            current.payload['state'] != 'pending' ||
            !SyncMetadata.sameOperation(current.payload, expected.payload)) {
          return false;
        }

        final history = await readRecord(
          'movements',
          expected.id,
          includeDeleted: true,
        );
        if (history?.ownerId != expected.ownerId ||
            history?.remotePresence != RemotePresence.confirmed ||
            history?.payload['_moveReceipt'] is! Map) {
          return false;
        }
        return _replaceRecordIfUnchanged(current, {
          ...current.payload,
          'state': 'completed',
        }, pending: false);
      });

  Future<bool> conflictAnimalMoveCommand(
    PendingRecord expected,
    String error,
  ) => transaction(() async {
    if (expected.collection != animalMoveCollection ||
        expected.ownerId == null) {
      return false;
    }

    await requireOwner(expected.ownerId!);

    final current = await readRecord(
      animalMoveCollection,
      expected.id,
      includeDeleted: true,
    );

    if (current == null ||
        current.payload['state'] != 'pending' ||
        !SyncMetadata.sameOperation(current.payload, expected.payload)) {
      return false;
    }

    final move = AnimalMoveCommand.fromLocal(current.payload);
    final animal = await readRecord(
      'animals',
      move.animalId,
      includeDeleted: true,
    );
    if (animal != null &&
        !animal.isDeleted &&
        animal.ownerId == expected.ownerId &&
        (animal.payload['_moveProjection'] as Map?)?['id'] == move.movementId) {
      await _writeRecord(
        'animals',
        animal.id,
        {
          ...animal.payload,
          '_moveProjection': {
            ...Map<String, Object?>.from(
              animal.payload['_moveProjection'] as Map,
            ),
            'rejected': true,
          },
        },
        animal.updatedAt,
        pending: (await readPendingRecords()).any(
          (r) => r.collection == 'animals' && r.id == animal.id,
        ),
      );
    }
    final history = await readRecord(
      'movements',
      move.movementId,
      includeDeleted: true,
    );
    if (history?.ownerId == expected.ownerId &&
        history?.remotePresence == RemotePresence.localOnly) {
      await _writeRecord(
        'movements',
        history!.id,
        {...history.payload, '_moveRejected': true},
        history.updatedAt,
        pending: false,
      );
    }
    return _replaceRecordIfUnchanged(current, {
      ...current.payload,
      'state': 'conflict',
      'error': error,
    }, pending: false);
  });

  Future<bool> reconcileRejectedAnimalMove(
    PendingRecord expected,
    Map<String, Object?> state,
  ) => transaction(() async {
    final owner = expected.ownerId;
    if (owner == null || expected.collection != animalMoveCollection) {
      return false;
    }
    await requireOwner(owner);
    final current = await readRecord(
      animalMoveCollection,
      expected.id,
      includeDeleted: true,
    );
    if (current == null ||
        current.payload['state'] != 'conflict' ||
        !SyncMetadata.sameOperation(current.payload, expected.payload)) {
      return false;
    }
    final move = AnimalMoveCommand.fromLocal(current.payload);
    final animal = await readRecord(
      'animals',
      move.animalId,
      includeDeleted: true,
    );
    if (animal == null || animal.ownerId != owner) return false;
    if (!animal.isDeleted) {
      final raw = state['animal'];
      if (raw is! Map ||
          raw['id'] != animal.id ||
          raw['user_id'] != owner ||
          !raw.containsKey('deleted_at') ||
          raw['deleted_at'] != null ||
          !raw.containsKey('paddock_id')) {
        return false;
      }
      final projection = animal.payload['_moveProjection'];
      if (projection is! Map || projection['id'] != move.movementId) {
        return false;
      }
      final next = {
        ...animal.payload,
        'paddockId': raw['paddock_id'],
        '_sync': {
          ...SyncMetadata.read(animal.payload),
          'revision': animal.revision + 1,
        },
      }..remove('_moveProjection');
      await _writeRecord(
        'animals',
        animal.id,
        next,
        animal.updatedAt,
        pending: (await readPendingRecords()).any(
          (r) => r.collection == 'animals' && r.id == animal.id,
        ),
      );
    }
    return _replaceRecordIfUnchanged(current, {
      ...current.payload,
      'reconciled': true,
    }, pending: false);
  });

  Future<bool> hasUnresolvedAnimalMoves() async {
    for (final payload in await readRecords(
      animalMoveCollection,
      includeDeleted: true,
    )) {
      if (payload['state'] != 'completed') {
        return true;
      }
    }

    return false;
  }
}
