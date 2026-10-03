import 'dart:convert';

import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_model.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_photo_upload.dart';
import 'package:mi_finca_app/features/animals/data/models/movement_model.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_move_command.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_patch.dart';

class AnimalLocalDataSource {
  const AnimalLocalDataSource(this._database);

  final AppDatabase _database;

  Future<String?> owner() => _database.localOwner();

  Future<PendingRecord?> record(String id) =>
      _database.readRecord('animals', id, includeDeleted: true);

  Future<bool> hasStoredAnimals() async =>
      (await _database.readRecords('animals', includeDeleted: true)).isNotEmpty;

  Future<bool> hasStoredMovements() async => (await _database.readRecords(
    'movements',
    includeDeleted: true,
  )).isNotEmpty;

  Future<AnimalLocalDeletion> deleteAnimal(String id, String owner) =>
      _database.deleteAnimalLocally(id, owner);

  Future<void> confirm(String id, String owner) =>
      _database.markRemoteConfirmed('animals', id, owner);

  Future<List<Animal>> getAll() async => (await _database.readRecords(
    'animals',
  )).map(AnimalModel.fromJson).toList();

  Future<List<Movement>> getMovements() async =>
      (await _database.readRecords('movements'))
          .where((p) => p['_moveRejected'] != true)
          .map(MovementModel.fromJson)
          .toList();

  Future<void> save(Animal animal, {bool pending = true}) {
    return _database.runInTransaction(() async {
      final previous = await _database.readRecord('animals', animal.id);
      final payload = AnimalModel.toJson(animal);

      if (pending) {
        payload['_animalWriteKind'] = previous == null
            ? 'create'
            : 'legacy_full_write';
      }

      if (pending) {
        final previousPayload = previous?.payload;
        final samePhoto =
            previousPayload != null &&
            AnimalPhotoUpload.localPath(previousPayload) ==
                animal.localPhotoPath;

        if (samePhoto) {
          // View models/forms may still hold the pre-upload Animal instance.
          // Preserve the durable job and newly published reference from SQLite.
          final job = AnimalPhotoUpload.read(previousPayload);
          if (job != null) {
            payload[AnimalPhotoUpload.key] = job;
            payload['remotePhotoPath'] = previousPayload['remotePhotoPath'];
          }
        } else if (animal.localPhotoPath != null) {
          final rawSession = await _database.readSetting('session');
          final owner = rawSession == null
              ? null
              : (jsonDecode(rawSession) as Map)['id'] as String?;

          payload[AnimalPhotoUpload.key] = AnimalPhotoUpload.create(
            animal.localPhotoPath!,
            owner,
          );

          if (previousPayload != null) {
            payload['remotePhotoPath'] = previousPayload['remotePhotoPath'];
          }
        }

        payload['syncStatus'] = 'pending';
      }

      await _database.putRecord(
        'animals',
        animal.id,
        payload,
        animal.updatedAt,
        pending: pending,
      );
    });
  }

  Future<void> edit(String id, AnimalPatch patch, {String? selectedPhoto}) =>
      _database.runInTransaction(() async {
        final owner = await _database.localOwner();
        if (owner == null) {
          throw StateError('Session required');
        }

        final before = await _database.readRecord(
          'animals',
          id,
          includeDeleted: true,
        );

        if (before == null ||
            before.ownerId != owner ||
            before.isDeleted ||
            before.payload['_animalConflict'] != null) {
          throw StateError('Animal unavailable');
        }

        final pendingBefore = (await _database.readPendingRecords()).any(
          (r) => r.collection == 'animals' && r.id == id,
        );

        if (pendingBefore &&
            ![
              'create',
              'photo',
            ].contains(SyncMetadata.read(before.payload)['writeKind'])) {
          throw StateError('LEGACY_LOCATION_AMBIGUOUS');
        }

        await _database.applyAnimalPatch(id, owner, patch);

        if (selectedPhoto != null) {
          final current = await _database.readRecord(
            'animals',
            id,
            includeDeleted: true,
          );

          if (current == null ||
              current.isDeleted ||
              current.ownerId != owner ||
              current.payload['_animalConflict'] != null) {
            throw StateError('Animal unavailable');
          }

          final kind =
              SyncMetadata.read(current.payload)['writeKind'] == 'create' &&
                  (await _database.readPendingRecords()).any(
                    (r) => r.collection == 'animals' && r.id == id,
                  )
              ? 'create'
              : 'photo';

          final changed = await _database.replaceRecordIfUnchanged(current, {
            ...current.payload,
            'localPhotoPath': selectedPhoto,
            AnimalPhotoUpload.key: AnimalPhotoUpload.create(
              selectedPhoto,
              owner,
            ),
            '_animalWriteKind': kind,
            '_sync': {
              ...SyncMetadata.read(current.payload),
              'writeKind': kind,
              'revision': current.revision + 1,
            },
          }, pending: true);

          if (!changed) {
            throw StateError('Animal changed during edit');
          }
        }
      });

  Future<AnimalRefreshSnapshot> snapshotForRefresh(String ownerId) =>
      _database.runInTransaction(() async {
        await _requireOwner(ownerId);

        return AnimalRefreshSnapshot(
          ownerId,
          {
            for (final payload in await _database.readRecords('animals'))
              payload['id']! as String: payload,
          },
          {
            for (final record in await _database.readPendingRecords())
              if (record.collection == 'animals') record.id,
          },
        );
      });

  Future<void> _requireOwner(String ownerId) async {
    final session = await _database.readSetting('session');

    if (session == null || (jsonDecode(session) as Map)['id'] != ownerId) {
      throw StateError('La sesión cambió durante la actualización.');
    }
  }

  Future<void> mergeRemoteAnimals(
    List<Animal> animals,
    AnimalRefreshSnapshot snapshot,
  ) => _database.runInTransaction(() async {
    await _requireOwner(snapshot.ownerId);

    final pending = {
      for (final record in await _database.readPendingRecords())
        if (record.collection == 'animals') record.id,
    };

    for (final animal in animals) {
      final current = await _database.readRecord('animals', animal.id);

      // Existence is positive evidence even when a pending edit blocks
      // content.
      await _database.markRemoteConfirmed(
        'animals',
        animal.id,
        snapshot.ownerId,
      );

      final photoPending =
          current != null &&
          SyncMetadata.read(current.payload)['writeKind'] == 'photo' &&
          pending.contains(animal.id);

      if (!photoPending &&
          (snapshot.pendingIds.contains(animal.id) ||
              pending.contains(animal.id))) {
        continue;
      }

      final previous = snapshot.payloads[animal.id];

      // Never overwrite a local edit (even already pushed) made during
      // the GET.
      if (current != null && previous != null) {
        if (!SyncMetadata.sameOperation(current.payload, previous)) {
          continue;
        }
      } else if (current != null || previous != null) {
        continue;
      }

      final job = current == null
          ? null
          : AnimalPhotoUpload.read(current.payload);

      final oldLocal = current == null
          ? null
          : AnimalPhotoUpload.localPath(current.payload);

      final oldRemote = current?.payload['remotePhotoPath'];

      if (!photoPending &&
          ((job != null && job['status'] != 'published') ||
              (oldLocal != null && oldRemote == null))) {
        continue;
      }

      final samePhoto = current != null && oldRemote == animal.remotePhotoPath;

      final payload = AnimalModel.toJson(
        animal.copyWith(
          localPhotoPath: samePhoto ? oldLocal : null,
          syncStatus: SyncStatus.synced,
        ),
      );

      if (samePhoto && job != null) {
        payload[AnimalPhotoUpload.key] = job;
      }

      if (photoPending) {
        payload['localPhotoPath'] = oldLocal;
        payload['remotePhotoPath'] = oldRemote;
        payload[AnimalPhotoUpload.key] = job;
        payload['_animalWriteKind'] = 'photo';
        payload['_sync'] = SyncMetadata.read(current.payload);

        await _database.replaceRecordIfUnchanged(
          current,
          await _database.overlayAnimalIntents(
            animal.id,
            snapshot.ownerId,
            payload,
          ),
          pending: true,
        );

        continue;
      }

      await _database.putRecord(
        'animals',
        animal.id,
        payload,
        animal.updatedAt,
        pending: false,
        verifiedRemoteOwner: snapshot.ownerId,
      );
    }

    // Missing remote rows are not deletions. No files are removed.
  });

  /// New DELETE D2 movement path.
  ///
  /// Persists the durable MOVE command and its local projection together.
  /// This must not be published as independent animal/movement writes.
  Future<void> saveAtomicMove(
    AnimalMoveCommand command,
    Movement movement,
  ) async {
    if (movement.id != command.movementId ||
        movement.animalId != command.animalId ||
        movement.fromPaddockId != command.fromPaddockId ||
        movement.toPaddockId != command.toPaddockId ||
        movement.date.toUtc() != command.movedAt.toUtc()) {
      throw StateError('MOVE command does not match movement.');
    }

    await _database.createAnimalMove(
      command: command,
      movementPayload: MovementModel.toJson(movement),
    );
  }

  /// Legacy movement path.
  ///
  /// Kept temporarily while DELETE D2 migrates all movement publication to
  /// sync_move_animal(). Do not use this for the new MOVE protocol.
  Future<void> saveMove(Animal animal, Movement movement) =>
      _database.runInTransaction(() async {
        final owner = await _database.localOwner();
        final current = await _database.readRecord('animals', animal.id);

        if (owner == null ||
            current == null ||
            current.ownerId != owner ||
            movement.animalId != animal.id ||
            current.payload['paddockId'] != movement.fromPaddockId) {
          throw StateError(
            'El animal ya no está disponible para este movimiento.',
          );
        }

        // Legacy behavior. This will be removed from the active movement
        // flow once sync_move_animal() is fully adopted.
        await save(animal);
        await saveMovement(movement);
      });

  Future<void> saveMovement(
    Movement movement, {
    bool pending = true,
    String? verifiedRemoteOwner,
  }) {
    return _database.runInTransaction(() async {
      if (pending) {
        final owner = await _database.localOwner();
        final parent = await _database.readRecord('animals', movement.animalId);

        if (owner == null || parent == null || parent.ownerId != owner) {
          throw StateError('El animal ya no está disponible para moverlo.');
        }

        await _database.requireOwner(owner);
      }

      await _database.putRecord(
        'movements',
        movement.id,
        MovementModel.toJson(movement),
        movement.date,
        pending: pending,
        verifiedRemoteOwner: verifiedRemoteOwner,
      );
    });
  }

  Future<void> markAnimalSynced(String id) {
    return _database.markRecordSynced('animals', id);
  }

  Future<void> markMovementSynced(String id) {
    return _database.markRecordSynced('movements', id);
  }
}

class AnimalRefreshSnapshot {
  const AnimalRefreshSnapshot(this.ownerId, this.payloads, this.pendingIds);

  final String ownerId;
  final Map<String, Map<String, Object?>> payloads;
  final Set<String> pendingIds;
}
