import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_failure.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/animals/data/services/animal_photo_sync.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/domain/repositories/sync_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SyncRepositoryImpl implements SyncRepository, TombstoneSyncRepository {
  SyncRepositoryImpl(this._local, this._remote, {AnimalPhotoSync? photos})
    : _photos = photos;

  final SyncLocalDataSource _local;
  final SyncRemoteDataSource _remote;
  final AnimalPhotoSync? _photos;

  Future<void>? _active;
  Future<void>? _discovery;
  Future<void>? _pull;

  Future<void> _discoverPhotos() =>
      _discovery ??= (_photos?.discoverLocalPhotos() ?? Future<void>.value())
          .whenComplete(() => _discovery = null);

  @override
  Stream<void> get changes => _local.changes;

  @override
  Future<int> pendingCount() async {
    await _discoverPhotos();
    return _local.pendingCount();
  }

  @override
  Future<DateTime?> lastSync() => _local.lastSync();

  @override
  Future<void> pushPendingChanges() =>
      _active ??= _push().whenComplete(() => _active = null);

  @override
  Future<void> pullRemoteTombstones() =>
      _pull ??= _pullTombstones().whenComplete(() => _pull = null);

  @override
  Future<void> markDeleted(String collection, String id, String ownerId) =>
      _local.markDeleted(collection, id, ownerId);

  @override
  Future<bool> verifyLegacyOwnership(
    String collection,
    String id,
    String ownerId,
  ) async {
    final remote = _remote;

    if (remote is! DeletionRemoteDataSource ||
        remote.currentUserId != ownerId) {
      return false;
    }

    await _local.requireOwner(ownerId);

    final snapshot = await _local.find(collection, id);

    if (snapshot == null || snapshot.isDeleted) {
      return false;
    }

    if (snapshot.ownerId != null) {
      return snapshot.ownerId == ownerId;
    }

    final photoOwner = (snapshot.payload['_photoUpload'] as Map?)?['ownerId'];
    final readRemotely = photoOwner != ownerId;

    if (readRemotely && !await remote.verifyLegacyOwner(snapshot, ownerId)) {
      return false;
    }

    if (remote.currentUserId != ownerId) {
      return false;
    }

    final adopted = await _local.adoptVerifiedOwner(snapshot, ownerId);

    if (readRemotely) {
      await _local.markRemoteConfirmed(collection, id, ownerId);
    }

    return adopted;
  }

  Future<void> _pullTombstones() async {
    final remote = _remote;

    if (remote is! DeletionRemoteDataSource) {
      return;
    }

    final owner = await _local.localOwner();

    if (owner == null || remote.currentUserId != owner) {
      throw StateError('La sesión de sincronización cambió.');
    }

    await _local.requireOwner(owner);

    final List<RemoteTombstone> tombstones;

    try {
      tombstones = await remote.fetchTombstones(owner);
    } on PostgrestException catch (error) {
      if (error.code == '42P01' || error.code == 'PGRST205') {
        return;
      }

      rethrow;
    }

    if (remote.currentUserId != owner) {
      throw StateError('La sesión cambió.');
    }

    await _local.mergeTombstones(owner, tombstones);
  }

  Future<void> _push() async {
    await _discoverPhotos();

    final records = await _local.readPendingRecords();

    var syncedCount = 0;

    final attempted = <String>{};
    final checkedParents = <String, bool>{};

    String key(PendingRecord record) => '${record.collection}/${record.id}';

    late Future<void> Function(PendingRecord) process;

    Future<bool> parentReady(String collection, String id, String owner) async {
      final parentKey = '$owner/$collection/$id';
      final transport = _remote;

      if (transport is! DeletionRemoteDataSource ||
          transport.currentUserId != owner) {
        return false;
      }

      await _local.requireOwner(owner);

      var parent = await _local.find(collection, id);

      if (parent?.ownerId != null && parent!.ownerId != owner) {
        return false;
      }

      if (parent?.remotePresence == RemotePresence.confirmed) {
        return true;
      }

      final cached = checkedParents[parentKey];

      if (cached != null) {
        return cached;
      }

      checkedParents[parentKey] = false;

      if (parent == null || parent.remotePresence == RemotePresence.unknown) {
        final probe =
            parent ??
            PendingRecord(
              collection: collection,
              id: id,
              payload: {'id': id},
              updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
            );

        final exists = await transport.verifyLegacyOwner(probe, owner);

        if (transport.currentUserId != owner) {
          throw StateError('La sesión cambió.');
        }

        await _local.requireOwner(owner);

        if (exists) {
          await _local.markRemoteConfirmed(collection, id, owner);

          checkedParents[parentKey] = true;

          return true;
        }
      }

      if (parent != null && !parent.isDeleted) {
        final candidates = await _local.readPendingRecords();

        final pending = candidates
            .where(
              (record) => record.collection == collection && record.id == id,
            )
            .firstOrNull;

        if (pending != null) {
          await process(pending);
        }
      }

      parent = await _local.find(collection, id);

      final ready =
          parent?.ownerId == owner &&
          parent?.remotePresence == RemotePresence.confirmed;

      checkedParents[parentKey] = ready;

      return ready;
    }

    Future<bool> dependenciesReady(PendingRecord record) async {
      if (record.collection != 'movements' || record.isDeleted) {
        return true;
      }

      final owner = record.ownerId;

      if (owner == null) {
        return false;
      }

      final paddocks = {
        record.payload['fromPaddockId'],
        record.payload['toPaddockId'],
      }.whereType<String>().toSet();

      for (final id in paddocks) {
        if (!await parentReady('paddocks', id, owner)) {
          return false;
        }
      }

      final animalId = record.payload['animalId'];

      return animalId is String &&
          await parentReady('animals', animalId, owner);
    }

    process = (initial) async {
      if (!attempted.add(key(initial))) {
        return;
      }

      var record = initial;

      try {
        final transport = _remote;

        if (record.collection == 'animals' &&
            !record.isDeleted &&
            record.ownerId == null &&
            ![
              'create',
              'photo',
            ].contains(SyncMetadata.read(record.payload)['writeKind'])) {
          await _local.quarantineAnimal(record);
          return;
        }

        if (transport is DeletionRemoteDataSource) {
          final owner = await _local.localOwner();

          if (owner == null || transport.currentUserId != owner) {
            return;
          }

          await _local.requireOwner(owner);

          if (record.ownerId == null && !record.isDeleted) {
            final photoOwner =
                (record.payload['_photoUpload'] as Map?)?['ownerId'];

            final readRemotely = photoOwner != owner;

            if (readRemotely &&
                !await transport.verifyLegacyOwner(record, owner)) {
              return;
            }

            if (transport.currentUserId != owner) {
              return;
            }

            if (!await _local.adoptVerifiedOwner(record, owner)) {
              return;
            }

            if (readRemotely) {
              await _local.markRemoteConfirmed(
                record.collection,
                record.id,
                owner,
              );
            }

            record = (await _local.current(record))!;
          }

          if (record.ownerId != owner) {
            return;
          }
        } else if (record.ownerId != null) {
          await _local.requireOwner(record.ownerId!);
        }

        if (record.collection == 'animals' &&
            !record.isDeleted &&
            ![
              'create',
              'photo',
            ].contains(SyncMetadata.read(record.payload)['writeKind'])) {
          await _local.quarantineAnimal(record);
          return;
        }

        if (!await dependenciesReady(record)) {
          return;
        }

        final current = await _local.current(record);

        if (current == null ||
            !SyncMetadata.sameOperation(current.payload, record.payload)) {
          return;
        }

        record = current;

        final bool confirmed;

        if (record.isDeleted) {
          if (transport is! DeletionRemoteDataSource) {
            return;
          }

          final tombstone = await transport.softDelete(record);

          if (transport.currentUserId != record.ownerId) {
            throw StateError('La sesión cambió.');
          }

          confirmed = await _local.acknowledgeDelete(record, tombstone);
        } else if (record.collection == 'animals' && _photos != null) {
          confirmed = await _photos.push(record, _remote.pushRecord);
        } else {
          final claimed = await _local.beginRemotePublish(record);

          if (claimed == null) {
            return;
          }

          final latest = await _local.current(claimed);

          if (latest == null ||
              latest.isDeleted ||
              !SyncMetadata.sameOperation(latest.payload, claimed.payload) ||
              latest.updatedAt != claimed.updatedAt) {
            return;
          }

          record = latest;

          await _remote.pushRecord(record);

          if (transport is DeletionRemoteDataSource &&
              transport.currentUserId != record.ownerId) {
            throw StateError('La sesión cambió.');
          }

          if (transport is DeletionRemoteDataSource && record.ownerId != null) {
            await _local.markRemoteConfirmed(
              record.collection,
              record.id,
              record.ownerId!,
            );
          }

          confirmed = await _local.acknowledge(record);
        }

        if (confirmed) {
          syncedCount++;
        }
      } catch (error) {
        if (record.collection == 'paddocks' &&
            _remote is DeletionRemoteDataSource &&
            _remote.currentUserId == record.ownerId &&
            record.isDeleted &&
            error is PostgrestException &&
            error.code == 'P0001' &&
            error.message == 'SYNC_PADDOCK_OCCUPIED') {
          try {
            await _local.rejectPaddockDelete(record, 'SYNC_PADDOCK_OCCUPIED');
          } catch (_) {
            // Session changes cannot mutate another
            // owner's operation.
          }
        }

        try {
          await pullRemoteTombstones();
        } catch (_) {
          // Preserve pending operations if
          // reconciliation isn't available.
        }
      }
    };

    // Generic outbox.
    //
    // Explicit PATCH and MOVE commands have their own
    // publication protocols below.
    for (final record in records) {
      if (record.collection == paddockPatchCollection ||
          record.collection == animalPatchCollection ||
          record.collection == animalMoveCollection) {
        continue;
      }

      await process(record);
    }

    // Paddock PATCH commands.
    final paddockReconciler = _remote;
    if (paddockReconciler is PaddockReconciliationRemoteDataSource) {
      final owner = await _local.localOwner();
      if (owner != null && paddockReconciler.currentUserId == owner) {
        for (final rejection in await _local.rejectedPaddockDeletes(owner)) {
          try {
            await pullRemoteTombstones();
            final active = await paddockReconciler.readActivePaddock(
              rejection.id,
              owner,
            );
            if (active != null && paddockReconciler.currentUserId == owner) {
              await _local.reconcilePaddockDelete(rejection, active);
            }
          } catch (_) {
            /* Keep durable rejection without authoritative evidence. */
          }
        }
      }
    }
    final patchTransport = _remote;

    if (patchTransport is PaddockPatchRemoteDataSource) {
      final owner = await _local.localOwner();

      if (owner != null && patchTransport.currentUserId == owner) {
        for (var command in await _local.patches(owner)) {
          try {
            if (patchTransport.currentUserId != owner ||
                !await _local.patchReady(command)) {
              continue;
            }

            if (command.payload['remoteBaseVersion'] == null) {
              final version = await patchTransport.paddockVersion(
                command.payload['entityId']! as String,
                owner,
              );

              if (patchTransport.currentUserId != owner) {
                break;
              }

              if (version == null) {
                await _local.finishPatch(
                  command,
                  error: 'PATCH_TARGET_UNAVAILABLE',
                );
                continue;
              }

              if (!await _local.bindPatchVersion(command, version)) {
                continue;
              }

              command = (await _local.current(command))!;
            }

            if (!await _local.patchReady(command)) {
              continue;
            }

            await patchTransport.pushPaddockPatch(command);

            if (patchTransport.currentUserId != owner) {
              break;
            }

            if (await _local.finishPatch(command)) {
              syncedCount++;
            }
          } on PostgrestException catch (error) {
            if (patchTransport.currentUserId == owner &&
                (error.code == 'P0001' ||
                    error.code == '42501' ||
                    error.code == '22023')) {
              await _local.finishPatch(command, error: error.message);
            }
          } catch (_) {
            // Retain the exact durable version on
            // uncertain delivery. Never rebase.
          }
        }
      }
    }

    // Animal PATCH commands.
    final animalTransport = _remote;

    if (animalTransport is AnimalPatchRemoteDataSource) {
      final owner = await _local.localOwner();

      if (owner != null && animalTransport.currentUserId == owner) {
        for (var command in await _local.animalPatches(owner)) {
          try {
            if (animalTransport.currentUserId != owner ||
                !await _local.animalPatchReady(command)) {
              continue;
            }

            if (command.payload['remoteBaseVersion'] == null) {
              final version = await animalTransport.animalVersion(
                command.payload['entityId']! as String,
                owner,
              );

              if (animalTransport.currentUserId != owner) {
                break;
              }

              if (version == null) {
                await _local.finishAnimalPatch(
                  command,
                  error: 'PATCH_TARGET_UNAVAILABLE',
                );
                continue;
              }

              if (!await _local.bindPatchVersion(command, version)) {
                continue;
              }

              command = (await _local.current(command))!;
            }

            if (!await _local.animalPatchReady(command)) {
              continue;
            }

            await animalTransport.pushAnimalPatch(command);

            if (animalTransport.currentUserId != owner) {
              break;
            }

            if (await _local.finishAnimalPatch(command)) {
              syncedCount++;
            }
          } on PostgrestException catch (error) {
            if (animalTransport.currentUserId == owner &&
                (error.code == 'P0001' ||
                    error.code == '42501' ||
                    error.code == '22023')) {
              await _local.finishAnimalPatch(command, error: error.message);
            }
          } catch (_) {
            // Retain the exact durable version on
            // uncertain delivery. Never rebase.
          }
        }
      }
    }

    // DELETE D2 MOVE commands.
    //
    // This is the ONLY remote publication path for a
    // new movement. The animal and movement projections
    // must never be independently upserted.
    final moveTransport = _remote;

    if (moveTransport is AnimalMoveRemoteDataSource) {
      final owner = await _local.localOwner();

      if (owner != null && moveTransport.currentUserId == owner) {
        for (final initial in await _local.animalMoves(owner)) {
          if (initial.payload['state'] == 'conflict' &&
              initial.payload['reconciled'] != true) {
            try {
              final state = await moveTransport.readAnimalMoveState(initial);
              if (moveTransport.currentUserId != owner) break;
              await pullRemoteTombstones();
              await _local.reconcileRejectedAnimalMove(initial, state);
            } catch (_) {
              /* Retain conflict until positive evidence arrives. */
            }
            continue;
          }
          if (initial.payload['state'] != 'pending') {
            continue;
          }

          var command = initial;

          try {
            if (moveTransport.currentUserId != owner) {
              break;
            }

            await _local.requireOwner(owner);

            final current = await _local.current(command);

            if (current == null ||
                current.ownerId != owner ||
                current.payload['state'] != 'pending' ||
                !SyncMetadata.sameOperation(current.payload, command.payload)) {
              continue;
            }

            command = current;

            // D1 is idempotent by movement_id.
            // If the previous HTTP response was lost,
            // retrying this exact command returns the
            // durable receipt instead of replaying the
            // movement.
            final movement = await moveTransport.pushAnimalMove(command);

            if (moveTransport.currentUserId != owner) {
              break;
            }

            await _local.requireOwner(owner);

            // The RPC only returns the movement row.
            // Read the authoritative post-RPC animal and
            // paddock state before clearing projections.
            final remoteState = await moveTransport.readAnimalMoveState(
              command,
            );

            if (moveTransport.currentUserId != owner) {
              break;
            }

            await _local.requireOwner(owner);

            if ((remoteState['animal'] as Map?)?['deleted_at'] != null ||
                (remoteState['paddocks'] as List?)?.any(
                      (p) => p is Map && p['deleted_at'] != null,
                    ) ==
                    true) {
              try {
                await pullRemoteTombstones();
              } catch (_) {
                /* Receipt is positive history evidence; no inferred deletion. */
              }
            }
            final reconciled = await _local.reconcileAnimalMoveSuccess(
              command,
              movement: movement,
              state: remoteState,
            );

            if (!reconciled) {
              // Never ACK from the RPC response alone if
              // the corresponding local projection could
              // not be reconciled safely.
              continue;
            }

            if (await _local.completeAnimalMove(command)) {
              syncedCount++;
            }
          } catch (error) {
            if (moveTransport.currentUserId != owner) {
              break;
            }

            final failure = SyncFailure.classify(error);

            if (failure == SyncFailureKind.businessConflict) {
              try {
                await _local.conflictAnimalMove(
                  command,
                  _moveConflictCode(error),
                );
                final conflict = await _local.current(command);
                final state = await moveTransport.readAnimalMoveState(command);
                if (moveTransport.currentUserId == owner && conflict != null) {
                  await _local.reconcileRejectedAnimalMove(conflict, state);
                }
              } catch (_) {
                // Never mutate an operation after its
                // owner/session changed.
              }

              // A terminal race may have caused the
              // business rejection. Pull authoritative
              // tombstones, but absence is never treated
              // as deletion.
              try {
                await pullRemoteTombstones();
              } catch (_) {
                // The durable MOVE conflict remains
                // available for later recovery.
              }
            }

            if (failure == SyncFailureKind.terminalEvidenceRequired) {
              try {
                await pullRemoteTombstones();
                final animal = await _local.find(
                  'animals',
                  command.payload['animalId']! as String,
                );
                final destination = await _local.find(
                  'paddocks',
                  command.payload['toPaddockId']! as String,
                );
                final sourceId = command.payload['fromPaddockId'];
                final source = sourceId is String
                    ? await _local.find('paddocks', sourceId)
                    : null;
                if (SyncMetadata.deletionState(animal?.payload ?? {}) ==
                        DeletionState.confirmed ||
                    SyncMetadata.deletionState(destination?.payload ?? {}) ==
                        DeletionState.confirmed ||
                    SyncMetadata.deletionState(source?.payload ?? {}) ==
                        DeletionState.confirmed) {
                  await _local.conflictAnimalMove(
                    command,
                    'SYNC_ENTITY_DELETED',
                  );
                  final conflict = await _local.current(command);
                  if (conflict != null) {
                    final state = animal?.isDeleted == true
                        ? <String, Object?>{'animal': null}
                        : await moveTransport.readAnimalMoveState(command);
                    await _local.reconcileRejectedAnimalMove(conflict, state);
                  }
                }
              } catch (_) {
                /* No terminal transition without positive evidence. */
              }
            }
            // Transient, unknown and authentication
            // failures intentionally leave the exact
            // command pending. Retrying the same
            // movement_id is safe because D1 is
            // idempotent.
          }
        }
      }
    }

    if (syncedCount > 0) {
      await _local.saveLastSync(DateTime.now());
    }
  }

  String _moveConflictCode(Object error) {
    final message = error is PostgrestException
        ? error.message
        : error.toString();

    const known = <String>[
      'SYNC_MOVE_SOURCE_CONFLICT',
      'SYNC_PADDOCK_NOT_AVAILABLE',
      'SYNC_GRAZING_DAYS_REQUIRED',
      'SYNC_MOVE_ID_CONFLICT',
      'SYNC_MOVE_LEGACY_CONFLICT',
      'SYNC_ENTITY_DELETED',
      'SYNC_NOT_AUTHORIZED',
    ];

    for (final code in known) {
      if (message.contains(code)) {
        return code;
      }
    }

    return 'SYNC_MOVE_CONFLICT';
  }
}
