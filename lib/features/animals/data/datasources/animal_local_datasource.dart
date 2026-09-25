import 'dart:convert';
import 'package:mi_finca_app/core/database/sync_metadata.dart';

import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_photo_upload.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_model.dart';
import 'package:mi_finca_app/features/animals/data/models/movement_model.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';

class AnimalLocalDataSource {
  const AnimalLocalDataSource(this._database);

  final AppDatabase _database;

  Future<List<Animal>> getAll() async => (await _database.readRecords(
    'animals',
  )).map(AnimalModel.fromJson).toList();

  Future<List<Movement>> getMovements() async => (await _database.readRecords(
    'movements',
  )).map(MovementModel.fromJson).toList();

  Future<void> save(Animal animal, {bool pending = true}) {
    return _database.runInTransaction(() async {
      final previous = await _database.readRecord('animals', animal.id);
      final payload = AnimalModel.toJson(animal);
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
      // Existence is positive evidence even when a pending edit blocks content.
      await _database.markRemoteConfirmed(
        'animals',
        animal.id,
        snapshot.ownerId,
      );
      if (snapshot.pendingIds.contains(animal.id) ||
          pending.contains(animal.id)) {
        continue;
      }
      final previous = snapshot.payloads[animal.id];
      // Never overwrite a local edit (even already pushed) made during the GET.
      if (current != null && previous != null) {
        if (!SyncMetadata.sameOperation(current.payload, previous)) continue;
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
      if ((job != null && job['status'] != 'published') ||
          (oldLocal != null && oldRemote == null)) {
        continue;
      }
      final samePhoto = current != null && oldRemote == animal.remotePhotoPath;
      final payload = AnimalModel.toJson(
        animal.copyWith(
          localPhotoPath: samePhoto ? oldLocal : null,
          syncStatus: SyncStatus.synced,
        ),
      );
      if (samePhoto && job != null) payload[AnimalPhotoUpload.key] = job;
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

  Future<void> saveMovement(
    Movement movement, {
    bool pending = true,
    String? verifiedRemoteOwner,
  }) {
    return _database.putRecord(
      'movements',
      movement.id,
      MovementModel.toJson(movement),
      movement.date,
      pending: pending,
      verifiedRemoteOwner: verifiedRemoteOwner,
    );
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
