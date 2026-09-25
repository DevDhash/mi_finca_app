import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';

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
      if (count > 0 || hasUnpublishedPhoto) throw const PendingSessionChanges();
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
      final next = {...payload};
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
      final oldMeta = SyncMetadata.read(current?.payload ?? {});
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
        if (pending && current?.isDeleted != true)
          'conflict': 'remote_delete_wins',
      };
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
    return replaceRecordIfUnchanged(expected, {
      ...expected.payload,
      SyncMetadata.key: {
        ...SyncMetadata.read(expected.payload),
        'deletedAt': remote.deletedAt.toUtc().toIso8601String(),
        'remoteOperationId': remote.operationId,
      },
    }, pending: false);
  });

  /// Compare the complete operation snapshot except independent presence evidence.
  /// A stale response cannot ACK another revision; current evidence is preserved.
  Future<bool> replaceRecordIfUnchanged(
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

  Future<void> removeRecord(String collection, String id) => transaction(
    () async {
      _requireWritableSession();
      if ((await readRecord(collection, id, includeDeleted: true))?.isDeleted ==
          true) {
        throw StateError('No se puede eliminar físicamente un tombstone.');
      }
      await customStatement(
        'DELETE FROM records WHERE collection = ? AND id = ?',
        [collection, id],
      );

      _recordChanges.add(null);
    },
  );

  Future<int> pendingCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS count FROM records WHERE pending = 1',
    ).getSingle();

    return row.read<int>('count');
  }

  Future<void> markRecordSynced(String collection, String id) => transaction(
    () async {
      _requireWritableSession();
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
    },
  );

  Future<void> markAllSynced() => transaction(() async {
    _requireWritableSession();
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
      if ((await readPendingRecords()).any((r) => r.isDeleted)) {
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
