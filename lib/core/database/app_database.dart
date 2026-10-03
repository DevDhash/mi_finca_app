import 'package:mi_finca_app/features/animals/domain/value_objects/animal_patch.dart';
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';

import 'package:uuid/uuid.dart';
import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_patch.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_move_command.dart';
part 'paddock_patch_store.dart';
part 'animal_patch_store.dart';
part 'animal_move_store.dart';

/// A small schema-less Drift store. Domain repositories own serialization,
/// which keeps the UI independent from both SQLite and a future REST backend.
final class AppDatabase extends GeneratedDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'mi_finca_mvp'));

  bool _closingSession = false;
  bool get isClosingSession => _closingSession;

  Future<void> beginSessionClose() async {
    if (_closingSession) {
      throw StateError('El cierre de sesión ya está en curso.');
    }
    _closingSession = true;
    try {
      final count = await pendingCount();
      final animals = await readRecords('animals');
      final hasUnpublishedPhoto = animals.any((payload) {
        final job = payload['_photoUpload'];
        final localPath = payload.containsKey('localPhotoPath')
            ? payload['localPhotoPath']
            : payload['photoPath'];
        return (job is Map && job['status'] != 'published') ||
            (localPath != null && payload['remotePhotoPath'] == null);
      });
      if (count > 0 ||
          hasUnpublishedPhoto ||
          await _hasDeletionConflicts() ||
          await hasUnresolvedAnimalMoves() ||
          await hasUnresolvedPaddockIntents() ||
          await hasUnresolvedAnimalIntents()) {
        throw const PendingSessionChanges();
      }
    } catch (_) {
      _closingSession = false;
      rethrow;
    }
  }

  void endSessionClose() => _closingSession = false;

  void _requireWritableSession() {
    if (_closingSession) {
      throw StateError('Espera a que termine el cierre de sesión.');
    }
  }

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo> get allTables => const [];

  final _recordChanges = StreamController<void>.broadcast();
  Stream<void> get recordChanges => _recordChanges.stream;

  Future<T> runInTransaction<T>(Future<T> Function() action) {
    return transaction(action);
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await customStatement('''
            CREATE TABLE records (
              collection TEXT NOT NULL,
              id TEXT NOT NULL,
              payload TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              pending INTEGER NOT NULL DEFAULT 1,
              PRIMARY KEY (collection, id)
            )
          ''');
      await customStatement('''
            CREATE TABLE settings (
              key TEXT PRIMARY KEY NOT NULL,
              value TEXT NOT NULL
            )
          ''');
    },
  );

  Future<List<Map<String, Object?>>> readRecords(
    String collection, {
    bool includeDeleted = false,
  }) async {
    final rows = await customSelect(
      'SELECT payload FROM records WHERE collection = ? ORDER BY updated_at DESC',
      variables: [Variable.withString(collection)],
    ).get();

    return rows
        .map(
          (row) => Map<String, Object?>.from(
            jsonDecode(row.read<String>('payload')) as Map,
          ),
        )
        .where((payload) => includeDeleted || !SyncMetadata.isDeleted(payload))
        .toList();
  }

  Future<List<PendingRecord>> readPendingRecords() async {
    final rows = await customSelect('''
      SELECT collection, id, payload, updated_at
      FROM records
      WHERE pending = 1
      ORDER BY updated_at ASC
      ''').get();

    return rows
        .map(
          (row) => PendingRecord(
            collection: row.read<String>('collection'),
            id: row.read<String>('id'),
            payload: Map<String, Object?>.from(
              jsonDecode(row.read<String>('payload')) as Map,
            ),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('updated_at'),
            ),
          ),
        )
        .toList();
  }

  Future<void> putRecord(
    String collection,
    String id,
    Map<String, Object?> payload,
    DateTime updatedAt, {
    bool pending = true,
    String? verifiedRemoteOwner,
  }) async {
    return transaction(() async {
      _requireWritableSession();
      if (verifiedRemoteOwner != null) {
        await _markRemoteConfirmedInTransaction(
          collection,
          id,
          verifiedRemoteOwner,
        );
      }
      final previous = await readRecord(collection, id, includeDeleted: true);
      if (previous?.isDeleted == true) {
        if (pending) throw StateError('El registro está eliminado.');
        return; // A stale active download must never resurrect a tombstone.
      }
      if (!pending &&
          (await readPendingRecords()).any(
            (r) => r.collection == collection && r.id == id,
          )) {
        return;
      }
      if (verifiedRemoteOwner != null) await requireOwner(verifiedRemoteOwner);
      final oldMeta = SyncMetadata.read(previous?.payload ?? {});
      final oldOwner = SyncMetadata.owner(previous?.payload ?? {});
      final sessionOwner = await localOwner();
      if (oldOwner != null && oldOwner != sessionOwner) {
        throw StateError('El registro pertenece a otra cuenta.');
      }
      // Only a NEW local operation can obtain ownership from the active session.
      // Editing an old unowned row is not evidence of its original ownership.
      final persistedPhotoOwner =
          (previous?.payload['_photoUpload'] as Map?)?['ownerId'] as String?;
      final owner =
          oldOwner ??
          verifiedRemoteOwner ??
          (persistedPhotoOwner == sessionOwner ? persistedPhotoOwner : null) ??
          (previous == null && pending ? sessionOwner : null);
      if (persistedPhotoOwner != null && persistedPhotoOwner != sessionOwner) {
        throw StateError('La foto pertenece a otra cuenta.');
      }
      if (collection == 'animals' &&
          pending &&
          previous != null &&
          (previous.payload['_animalConflict'] != null ||
              previous.payload['_moveProjection'] != null ||
              (owner != null &&
                  (await animalPatches(
                    owner,
                    entityId: id,
                  )).any((r) => r.payload['state'] != 'completed')))) {
        throw StateError(
          'Use explicit animal intent; unresolved operations exist',
        );
      }
      if (collection == 'paddocks' &&
          pending &&
          previous != null &&
          (previous.payload['_moveProjection'] != null ||
              (owner != null &&
                  (await paddockPatches(
                    owner,
                    entityId: id,
                  )).any((r) => r.payload['state'] != 'completed')))) {
        throw StateError(
          'Usa intención explícita; hay cambios de potrero pendientes.',
        );
      }
      final next = collection == 'animals' && !pending && owner != null
          ? await overlayAnimalIntents(id, owner, payload)
          : collection == 'paddocks' && !pending && owner != null
          ? await overlayPaddockIntents(id, owner, payload)
          : {...payload};
      if (pending) {
        next[SyncMetadata.key] = SyncMetadata.operation(
          ownerId: owner,
          operation: 'upsert',
          revision: (oldMeta['revision'] as int? ?? 0) + 1,
          requestedAt: DateTime.now(),
        );
      } else if (verifiedRemoteOwner != null) {
        next[SyncMetadata.key] = {
          ...SyncMetadata.operation(
            ownerId: verifiedRemoteOwner,
            operation: 'upsert',
            revision: (oldMeta['revision'] as int? ?? 0) + 1,
            requestedAt: updatedAt,
          ),
          'ownership': 'verified_remote',
        };
      } else if (oldMeta.isNotEmpty) {
        next[SyncMetadata.key] = oldMeta;
      } else {
        next.remove(SyncMetadata.key);
      }
      if (collection == 'animals' && pending) {
        next[SyncMetadata.key] = {
          ...SyncMetadata.read(next),
          'writeKind': payload['_animalWriteKind'] ?? 'legacy_full_write',
        };
      }
      if (collection == 'paddocks' && pending) {
        next[SyncMetadata.key] = {
          ...SyncMetadata.read(next),
          'writeKind': previous == null ? 'create' : 'legacy_full_write',
        };
      }
      if (oldMeta['deleteRejection'] != null) {
        next[SyncMetadata.key] = {
          ...SyncMetadata.read(next),
          'deleteRejection': oldMeta['deleteRejection'],
          'rejectedDelete': oldMeta['rejectedDelete'] ?? oldMeta,
        };
      }
      if (SyncMetadata.collections.contains(collection)) {
        final presence = verifiedRemoteOwner != null
            ? RemotePresence.confirmed
            : previous != null
            ? previous.remotePresence
            : pending && owner != null
            ? RemotePresence.localOnly
            : RemotePresence.unknown;
        next[SyncMetadata.key] = {
          ...SyncMetadata.read(next),
          'remotePresence': SyncMetadata.presenceValue(presence),
        };
      }
      await _writeRecord(collection, id, next, updatedAt, pending: pending);
    });
  }

  Future<void> _writeRecord(
    String collection,
    String id,
    Map<String, Object?> payload,
    DateTime updatedAt, {
    required bool pending,
  }) async {
    await customStatement(
      'INSERT OR REPLACE INTO records '
      '(collection, id, payload, updated_at, pending) VALUES (?, ?, ?, ?, ?)',
      [
        collection,
        id,
        jsonEncode(payload),
        updatedAt.millisecondsSinceEpoch,
        pending ? 1 : 0,
      ],
    );
    _recordChanges.add(null);
  }

  Future<String?> localOwner() async {
    final raw = await readSetting('session');
    return raw == null ? null : (jsonDecode(raw) as Map)['id'] as String?;
  }

  Future<void> requireOwner(String ownerId) async {
    _requireWritableSession();
    if (ownerId.isEmpty || await localOwner() != ownerId) {
      throw StateError('La operación pertenece a otra sesión.');
    }
  }

  Future<PendingRecord?> readRecord(
    String collection,
    String id, {
    bool includeDeleted = false,
  }) async {
    final row = await customSelect(
      'SELECT payload, updated_at FROM records WHERE collection = ? AND id = ?',
      variables: [Variable.withString(collection), Variable.withString(id)],
    ).getSingleOrNull();
    if (row == null) return null;
    final record = PendingRecord(
      collection: collection,
      id: id,
      payload: Map<String, Object?>.from(
        jsonDecode(row.read<String>('payload')) as Map,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at'),
      ),
    );
    return !includeDeleted && record.isDeleted ? null : record;
  }

  /// Durable intent, not physical removal. Ownership must already be proven.
  Future<void> markDeleted(String collection, String id, String ownerId) =>
      transaction(() => _markDeletedInTransaction(collection, id, ownerId));

  Future<void> _markDeletedInTransaction(
    String collection,
    String id,
    String ownerId,
  ) async {
    await requireOwner(ownerId);
    if (!SyncMetadata.collections.contains(collection)) {
      throw ArgumentError.value(collection, 'collection');
    }
    final record = await readRecord(collection, id, includeDeleted: true);
    if (record == null) throw StateError('El registro no existe localmente.');
    if (record.ownerId != ownerId) {
      throw StateError('Propietario no verificado para este registro.');
    }
    if (record.isDeleted) return; // Keep identity, revision and ack unchanged.
    if (collection == 'paddocks') {
      if ((await readRecords(
        'animals',
      )).any((p) => SyncMetadata.owner(p) == ownerId && p['paddockId'] == id)) {
        throw StateError('SYNC_PADDOCK_OCCUPIED');
      }
      if ((await animalMoveCommands(ownerId)).any(
        (r) =>
            r.payload['state'] != 'completed' &&
            (r.payload['fromPaddockId'] == id ||
                r.payload['toPaddockId'] == id),
      )) {
        throw StateError('Resolve pending MOVE before deletion');
      }
    }
    if (collection == 'paddocks' && record.payload['_moveProjection'] != null) {
      throw StateError('Resuelve el movimiento pendiente antes de eliminar.');
    }
    if (SyncMetadata.read(record.payload)['deleteRejection'] != null) {
      throw StateError(
        'Resuelve el conflicto de eliminación antes de reintentar.',
      );
    }
    final now = DateTime.now();
    final meta = SyncMetadata.operation(
      ownerId: ownerId,
      operation: 'delete',
      revision: record.revision + 1,
      requestedAt: now,
    );
    await _writeRecord(
      collection,
      id,
      {
        ...record.payload,
        SyncMetadata.key: {
          ...meta,
          'remotePresence': SyncMetadata.presenceValue(record.remotePresence),
          'deletionState': 'pending',
        },
      },
      now,
      pending: true,
    );
  }

  /// Competes with beginRemotePublish in the same SQLite transaction. No remote ACK.
  Future<AnimalLocalDeletion> deleteAnimalLocally(String id, String owner) =>
      transaction(() async {
        await requireOwner(owner);
        final animal = await readRecord('animals', id, includeDeleted: true);
        if (animal == null) return AnimalLocalDeletion.notFound;
        if (animal.ownerId != owner) {
          return AnimalLocalDeletion.needsVerification;
        }
        final photoOwner = (animal.payload['_photoUpload'] as Map?)?['ownerId'];
        if (photoOwner != null && photoOwner != owner) {
          return AnimalLocalDeletion.needsVerification;
        }
        if (animal.isDeleted) return AnimalLocalDeletion.alreadyDeleted;
        if (animal.remotePresence == RemotePresence.confirmed) {
          await _markDeletedInTransaction('animals', id, owner);
          return AnimalLocalDeletion.accepted;
        }
        if (animal.remotePresence != RemotePresence.localOnly) {
          return AnimalLocalDeletion.needsVerification;
        }
        final pending = (await readPendingRecords())
            .map((r) => '${r.collection}/${r.id}')
            .toSet();
        bool cancellable(PendingRecord record) {
          final meta = SyncMetadata.read(record.payload);
          return record.ownerId == owner &&
              record.remotePresence == RemotePresence.localOnly &&
              meta['deletedAt'] == null &&
              meta['remoteOperationId'] == null &&
              (record.isDeleted
                  ? meta['localCancellation'] == true
                  : record.operation == 'upsert' &&
                        record.operationId != null &&
                        record.revision > 0 &&
                        pending.contains('${record.collection}/${record.id}'));
        }

        final photo = animal.payload['_photoUpload'] as Map?;
        if (!cancellable(animal) ||
            animal.payload['remotePhotoPath'] != null ||
            photo?['target'] != null ||
            photo?['status'] == 'uploaded' ||
            photo?['status'] == 'published') {
          return AnimalLocalDeletion.needsVerification;
        }
        final dependents = <PendingRecord>[];
        for (final payload in await readRecords(
          'movements',
          includeDeleted: true,
        )) {
          if (payload['animalId'] != id) continue;
          final movement = (await readRecord(
            'movements',
            payload['id']! as String,
            includeDeleted: true,
          ))!;
          if (!cancellable(movement)) {
            return AnimalLocalDeletion.needsVerification;
          }
          dependents.add(movement);
        }
        // Validate every dependent before writing any cancellation.
        final now = DateTime.now();
        for (final record in [...dependents, animal]) {
          if (record.isDeleted) continue;
          await _writeRecord(
            record.collection,
            record.id,
            {
              ...record.payload,
              SyncMetadata.key: {
                ...SyncMetadata.read(record.payload),
                ...SyncMetadata.operation(
                  ownerId: owner,
                  operation: 'cancel',
                  revision: record.revision + 1,
                  requestedAt: now,
                ),
                'tombstone': true,
                'localCancellation': true,
                'remotePresence': 'local_only',
              },
            },
            now,
            pending: false,
          );
        }
        return AnimalLocalDeletion.accepted;
      });

  /// Call only after an authenticated remote ownership check for this snapshot.
  Future<bool> adoptVerifiedOwner(PendingRecord expected, String ownerId) =>
      transaction(() async {
        await requireOwner(ownerId);
        if (expected.ownerId != null && expected.ownerId != ownerId) {
          throw StateError('El registro pertenece a otra cuenta.');
        }
        final photoOwner =
            (expected.payload['_photoUpload'] as Map?)?['ownerId'];
        if (photoOwner != null && photoOwner != ownerId) {
          throw StateError('La foto pertenece a otra cuenta.');
        }
        final pending = (await readPendingRecords()).any(
          (r) => r.collection == expected.collection && r.id == expected.id,
        );
        final meta = SyncMetadata.read(expected.payload);
        return replaceRecordIfUnchanged(expected, {
          ...expected.payload,
          SyncMetadata.key: {
            if (meta.isEmpty)
              ...SyncMetadata.operation(
                ownerId: ownerId,
                operation: 'upsert',
                revision: 1,
                requestedAt: expected.updatedAt,
              ),
            ...meta,
            'ownerId': ownerId,
            'ownership': 'verified',
          },
        }, pending: pending);
      });

  Future<void> mergeRemoteTombstones(
    String ownerId,
    List<RemoteTombstone> tombstones,
  ) => transaction(() async {
    await requireOwner(ownerId);
    for (final remote in tombstones) {
      if (remote.ownerId != ownerId ||
          !SyncMetadata.collections.contains(remote.collection)) {
        throw StateError('Tombstone remoto inválido.');
      }
      final current = await readRecord(
        remote.collection,
        remote.id,
        includeDeleted: true,
      );
      if (current?.ownerId != null && current!.ownerId != ownerId) {
        throw StateError('El registro local pertenece a otra cuenta.');
      }
      final photoOwner = (current?.payload['_photoUpload'] as Map?)?['ownerId'];
      if (photoOwner != null && photoOwner != ownerId) {
        throw StateError('La foto local pertenece a otra cuenta.');
      }
      final pending = (await readPendingRecords()).any(
        (r) => r.collection == remote.collection && r.id == remote.id,
      );
      final oldMeta = SyncMetadata.read(current?.payload ?? {})
        ..remove('deleteRejection');
      final meta = {
        ...oldMeta,
        'ownerId': ownerId,
        'ownership': 'verified',
        'operation': 'delete',
        'tombstone': true,
        'operationId': current?.isDeleted == true
            ? oldMeta['operationId']
            : remote.operationId,
        'revision': current?.isDeleted == true
            ? current!.revision
            : (current?.revision ?? 0) + 1,
        'requestedAt':
            oldMeta['requestedAt'] ?? remote.deletedAt.toIso8601String(),
        'deletedAt': remote.deletedAt.toUtc().toIso8601String(),
        'remoteOperationId': remote.operationId,
        'deletionState': 'confirmed',
        if (pending && current?.isDeleted != true)
          'conflict': 'remote_delete_wins',
      };
      if (remote.collection == 'animals') {
        await conflictAnimalPatches(remote.id, ownerId);
      }
      if (remote.collection == 'paddocks') {
        await conflictPaddockPatches(remote.id, ownerId);
      }
      // Keep domain/photo bytes for history and future cleanup, never upload them.
      await _writeRecord(
        remote.collection,
        remote.id,
        {...?current?.payload, 'id': remote.id, SyncMetadata.key: meta},
        current?.updatedAt ?? remote.deletedAt,
        pending: false,
      );
    }
  });

  Future<bool> acknowledgeDelete(
    PendingRecord expected,
    RemoteTombstone remote,
  ) => transaction(() async {
    if (!expected.isDeleted ||
        expected.ownerId != remote.ownerId ||
        expected.collection != remote.collection ||
        expected.id != remote.id) {
      throw StateError('Confirmación DELETE inválida.');
    }
    await requireOwner(remote.ownerId);
    final acknowledged = await replaceRecordIfUnchanged(expected, {
      ...expected.payload,
      SyncMetadata.key: {
        ...(SyncMetadata.read(expected.payload)..remove('deleteRejection')),
        'deletedAt': remote.deletedAt.toUtc().toIso8601String(),
        'remoteOperationId': remote.operationId,
        'deletionState': 'confirmed',
      },
    }, pending: false);
    if (acknowledged && expected.collection == 'animals') {
      await conflictAnimalPatches(expected.id, remote.ownerId);
    }
    if (acknowledged && expected.collection == 'paddocks') {
      await conflictPaddockPatches(expected.id, remote.ownerId);
    }
    return acknowledged;
  });

  Future<DeletionState> deletionState(String collection, String id) =>
      transaction(() async {
        final record = await readRecord(collection, id, includeDeleted: true);
        if (record == null) return DeletionState.active;
        final state = SyncMetadata.deletionState(record.payload);
        if (state != DeletionState.legacyUnknown) return state;
        final meta = SyncMetadata.read(record.payload);
        final pending = (await readPendingRecords()).any(
          (r) => r.collection == collection && r.id == id,
        );
        if (pending &&
            record.operation == 'delete' &&
            record.ownerId != null &&
            record.operationId != null &&
            record.revision > 0 &&
            meta['deletedAt'] == null &&
            meta['remoteOperationId'] == null &&
            meta['localCancellation'] != true) {
          return DeletionState.pending;
        }
        // Unrecognized/corrupt data is not classified by a heuristic.
        return DeletionState.legacyUnknown;
      });

  /// Positive business rejection only. Does not infer rejection from missing
  /// ledger rows, HTTP failures, or absence of remote data.
  Future<bool> rejectPaddockDelete(PendingRecord expected, String code) =>
      transaction(() async {
        if (code != 'SYNC_PADDOCK_OCCUPIED' ||
            expected.collection != 'paddocks' ||
            expected.ownerId == null ||
            expected.operationId == null ||
            expected.revision < 1 ||
            expected.operation != 'delete') {
          throw ArgumentError('Invalid paddock deletion rejection');
        }
        await requireOwner(expected.ownerId!);
        final state = SyncMetadata.deletionState(expected.payload);
        final pending = (await readPendingRecords()).any(
          (r) => r.collection == expected.collection && r.id == expected.id,
        );
        if (!pending ||
            !expected.isDeleted ||
            (state != DeletionState.pending &&
                state != DeletionState.legacyUnknown)) {
          return false;
        }
        final meta = SyncMetadata.read(expected.payload);
        // Partial acknowledgement evidence must never be downgraded.
        if (meta['deletedAt'] != null ||
            meta['remoteOperationId'] != null ||
            meta['localCancellation'] == true) {
          return false;
        }
        return replaceRecordIfUnchanged(expected, {
          ...expected.payload,
          SyncMetadata.key: {
            ...meta,
            'deletionState': 'conflict',
            'deleteRejection': code,
          },
        }, pending: false);
      });

  /// Caller must provide an authenticated, owner-filtered ACTIVE server row
  /// serialized in local format, read after the positive business rejection.
  /// This explicit path is never used by ordinary downloads/putRecord.
  Future<bool> reconcileRejectedPaddockDelete(
    PendingRecord expected, {
    required String remoteOwner,
    required Map<String, Object?> activePayload,
  }) => transaction(() async {
    await requireOwner(remoteOwner);
    if (expected.ownerId != remoteOwner ||
        expected.collection != 'paddocks' ||
        activePayload['id'] != expected.id ||
        activePayload['user_id'] != remoteOwner ||
        !activePayload.containsKey('deleted_at') ||
        activePayload.containsKey(SyncMetadata.key) ||
        activePayload['deleted_at'] != null ||
        activePayload['deletedAt'] != null) {
      throw ArgumentError('Invalid authoritative active paddock');
    }
    final current = await readRecord(
      'paddocks',
      expected.id,
      includeDeleted: true,
    );
    if (current == null ||
        current.updatedAt != expected.updatedAt ||
        !SyncMetadata.sameOperation(current.payload, expected.payload) ||
        SyncMetadata.deletionState(current.payload) != DeletionState.conflict) {
      return false;
    }
    final meta = SyncMetadata.read(current.payload);
    if (meta['deleteRejection'] != 'SYNC_PADDOCK_OCCUPIED' ||
        meta['deletedAt'] != null ||
        meta['remoteOperationId'] != null ||
        current.operationId == null ||
        current.revision < 1) {
      return false;
    }
    await _writeRecord(
      'paddocks',
      current.id,
      {
        ...activePayload,
        SyncMetadata.key: {
          ...meta,
          'tombstone': false,
          'deletionState': 'reconciledConflict',
          'remotePresence': 'confirmed',
        },
      },
      current.updatedAt,
      pending: false,
    );
    return true;
  });

  Future<bool> _hasDeletionConflicts() async {
    final rows = await customSelect('SELECT payload FROM records').get();
    return rows.any((row) {
      final meta = SyncMetadata.read(
        Map<String, Object?>.from(
          jsonDecode(row.read<String>('payload')) as Map,
        ),
      );
      return meta['deleteRejection'] != null;
    });
  }

  /// Compare the complete operation snapshot except independent presence evidence.
  /// A stale response cannot ACK another revision; current evidence is preserved.
  Future<bool> replaceRecordIfUnchanged(
    PendingRecord expected,
    Map<String, Object?> payload, {
    required bool pending,
  }) {
    if (expected.collection == animalMoveCollection) {
      throw StateError('MOVE requires explicit transition');
    }
    return _replaceRecordIfUnchanged(expected, payload, pending: pending);
  }

  Future<bool> _replaceRecordIfUnchanged(
    PendingRecord expected,
    Map<String, Object?> payload, {
    required bool pending,
  }) => transaction(() async {
    if (_closingSession) return false;
    if (expected.ownerId != null && await localOwner() != expected.ownerId) {
      return false;
    }
    final current = await readRecord(
      expected.collection,
      expected.id,
      includeDeleted: true,
    );
    if (current == null ||
        current.updatedAt.millisecondsSinceEpoch !=
            expected.updatedAt.millisecondsSinceEpoch ||
        !SyncMetadata.sameOperation(current.payload, expected.payload)) {
      return false;
    }
    if (current.isDeleted && !SyncMetadata.isDeleted(payload)) return false;
    final oldMeta = SyncMetadata.read(current.payload);
    final newMeta = SyncMetadata.read(payload);
    if (SyncMetadata.deletionState(current.payload) ==
            DeletionState.confirmed &&
        (newMeta['deletedAt'] != oldMeta['deletedAt'] ||
            newMeta['remoteOperationId'] != oldMeta['remoteOperationId'])) {
      return false;
    }

    if (oldMeta['deleteRejection'] != null &&
        newMeta['deleteRejection'] != oldMeta['deleteRejection'] &&
        SyncMetadata.deletionState(payload) != DeletionState.confirmed) {
      return false;
    }
    final next = {...payload};
    final presence = current.remotePresence;
    next[SyncMetadata.key] = {
      ...SyncMetadata.read(next),
      'remotePresence': SyncMetadata.presenceValue(presence),
    };
    await _writeRecord(
      expected.collection,
      expected.id,
      next,
      current.updatedAt,
      pending: pending,
    );
    return true;
  });

  /// Atomic publication claim. A future local cancellation must compete with
  /// this transaction: once claimed, this identity is never "never sent" again.
  Future<PendingRecord?> beginRemotePublish(PendingRecord expected) =>
      transaction(() async {
        _requireWritableSession();
        if (expected.ownerId != null) await requireOwner(expected.ownerId!);
        final current = await readRecord(
          expected.collection,
          expected.id,
          includeDeleted: true,
        );
        if (current == null ||
            current.isDeleted ||
            current.updatedAt.millisecondsSinceEpoch !=
                expected.updatedAt.millisecondsSinceEpoch ||
            !SyncMetadata.sameOperation(current.payload, expected.payload)) {
          return null;
        }
        if (!(await readPendingRecords()).any(
          (r) => r.collection == current.collection && r.id == current.id,
        )) {
          return null;
        }
        if (current.remotePresence != RemotePresence.localOnly) return current;
        final payload = {
          ...current.payload,
          SyncMetadata.key: {
            ...SyncMetadata.read(current.payload),
            'remotePresence': 'unknown',
          },
        };
        await _writeRecord(
          current.collection,
          current.id,
          payload,
          current.updatedAt,
          pending: true,
        );
        return PendingRecord(
          collection: current.collection,
          id: current.id,
          payload: payload,
          updatedAt: current.updatedAt,
        );
      });

  /// Only callers holding a positive authenticated row read / UPSERT result
  /// may call this. Never called for Storage or a deletion-ledger response.
  /// Evidence can outlive a revision, but cannot ACK it or restore its payload.
  Future<void> markRemoteConfirmed(
    String collection,
    String id,
    String owner,
  ) => transaction(
    () => _markRemoteConfirmedInTransaction(collection, id, owner),
  );

  /// Caller must already hold the transaction. Public callers use the wrapper;
  /// putRecord shares its own atomic unit instead of opening another savepoint.
  Future<void> _markRemoteConfirmedInTransaction(
    String collection,
    String id,
    String owner,
  ) async {
    await requireOwner(owner);
    if (!SyncMetadata.collections.contains(collection)) {
      throw ArgumentError.value(collection);
    }
    final current = await readRecord(collection, id, includeDeleted: true);
    if (current == null) return;
    final photoOwner = (current.payload['_photoUpload'] as Map?)?['ownerId'];
    if ((current.ownerId != null && current.ownerId != owner) ||
        (photoOwner != null && photoOwner != owner)) {
      throw StateError('La evidencia pertenece a otra cuenta.');
    }
    if (current.remotePresence == RemotePresence.confirmed) return;
    final pending = (await readPendingRecords()).any(
      (r) => r.collection == collection && r.id == id,
    );
    await _writeRecord(
      collection,
      id,
      {
        ...current.payload,
        SyncMetadata.key: {
          ...SyncMetadata.read(current.payload),
          'ownerId': owner,
          if (current.ownerId == null) 'ownership': 'verified_remote',
          'remotePresence': 'confirmed',
        },
      },
      current.updatedAt,
      pending: pending,
    );
  }

  Future<void> removeRecord(
    String collection,
    String id,
  ) => transaction(() async {
    _requireWritableSession();
    if ((await readRecord(collection, id, includeDeleted: true))?.isDeleted ==
        true) {
      throw StateError('No se puede eliminar físicamente un tombstone.');
    }
    if (collection == animalMoveCollection ||
        (collection == 'movements' &&
            await readRecord(animalMoveCollection, id, includeDeleted: true) !=
                null) ||
        (collection == 'movements' &&
            (await readRecord(
                  collection,
                  id,
                  includeDeleted: true,
                ))?.payload['_moveReceipt'] !=
                null) ||
        collection == animalPatchCollection ||
        (collection == 'animals' && await hasUnresolvedAnimalIntents()) ||
        collection == paddockPatchCollection ||
        (collection == 'paddocks' &&
            (await hasUnresolvedPaddockIntents() ||
                await hasUnresolvedAnimalIntents()))) {
      throw const PendingSessionChanges();
    }
    final record = await readRecord(collection, id, includeDeleted: true);
    if (SyncMetadata.read(record?.payload ?? {})['deleteRejection'] != null) {
      throw const PendingSessionChanges();
    }
    await customStatement(
      'DELETE FROM records WHERE collection = ? AND id = ?',
      [collection, id],
    );

    _recordChanges.add(null);
  });

  Future<int> pendingCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS count FROM records WHERE pending = 1',
    ).getSingle();

    return row.read<int>('count');
  }

  Future<void> markRecordSynced(
    String collection,
    String id,
  ) => transaction(() async {
    _requireWritableSession();
    if (collection == animalMoveCollection ||
        (collection == 'movements' &&
            await readRecord(animalMoveCollection, id, includeDeleted: true) !=
                null) ||
        (collection == 'movements' &&
            (await readRecord(
                  collection,
                  id,
                  includeDeleted: true,
                ))?.payload['_moveReceipt'] !=
                null) ||
        collection == animalPatchCollection ||
        (collection == 'animals' && await hasUnresolvedAnimalIntents()) ||
        collection == paddockPatchCollection ||
        (collection == 'paddocks' &&
            (await hasUnresolvedPaddockIntents() ||
                await hasUnresolvedAnimalIntents()))) {
      throw StateError('Las intenciones de potrero requieren ACK individual.');
    }
    if ((await readRecord(collection, id, includeDeleted: true))?.isDeleted ==
        true) {
      throw StateError('DELETE requiere confirmación por snapshot.');
    }
    await customStatement(
      '''
      UPDATE records
      SET pending = 0
      WHERE collection = ? AND id = ?
      ''',
      [collection, id],
    );

    _recordChanges.add(null);
  });

  Future<void> markAllSynced() => transaction(() async {
    _requireWritableSession();
    if ((await hasUnresolvedAnimalMoves() ||
        await hasUnresolvedPaddockIntents() ||
        await hasUnresolvedAnimalIntents())) {
      throw StateError('Las intenciones de potrero requieren ACK individual.');
    }
    if ((await readPendingRecords()).any((r) => r.isDeleted)) {
      throw StateError('DELETE requiere confirmación individual.');
    }
    await customStatement('UPDATE records SET pending = 0');
    _recordChanges.add(null);
  });

  Future<String?> readSetting(String key) async {
    final row = await customSelect(
      'SELECT value FROM settings WHERE key = ?',
      variables: [Variable.withString(key)],
    ).getSingleOrNull();

    return row?.read<String>('value');
  }

  Future<void> writeSetting(String key, String value) async {
    _requireWritableSession();
    await customStatement(
      'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
      [key, value],
    );
  }

  Future<void> deleteSetting(String key) =>
      customStatement('DELETE FROM settings WHERE key = ?', [key]);

  Future<void> clearAll() async {
    await transaction(() async {
      if (await _hasDeletionConflicts() ||
          await hasUnresolvedAnimalMoves() ||
          await hasUnresolvedPaddockIntents() ||
          await hasUnresolvedAnimalIntents() ||
          (await readPendingRecords()).any((r) => r.isDeleted)) {
        throw const PendingSessionChanges();
      }
      await customStatement('DELETE FROM records');
      await customStatement('DELETE FROM settings');
    });

    _recordChanges.add(null);
  }

  @override
  Future<void> close() async {
    await _recordChanges.close();
    await super.close();
  }
}

class PendingRecord {
  const PendingRecord({
    required this.collection,
    required this.id,
    required this.payload,
    required this.updatedAt,
  });

  final String collection;
  final String id;
  final Map<String, Object?> payload;
  final DateTime updatedAt;
  RemotePresence get remotePresence => SyncMetadata.presence(payload);
  bool get isDeleted => SyncMetadata.isDeleted(payload);
  String? get ownerId => SyncMetadata.owner(payload);
  String get operation =>
      SyncMetadata.read(payload)['operation'] as String? ?? 'upsert';
  String? get operationId =>
      SyncMetadata.read(payload)['operationId'] as String?;
  int get revision => SyncMetadata.read(payload)['revision'] as int? ?? 0;
}

enum AnimalLocalDeletion {
  accepted,
  needsVerification,
  notFound,
  alreadyDeleted,
}

class PendingSessionChanges implements Exception {
  const PendingSessionChanges();
  @override
  String toString() =>
      'Sincroniza los cambios y las fotos pendientes antes de cerrar sesión.';
}
