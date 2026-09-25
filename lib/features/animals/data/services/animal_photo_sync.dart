import 'dart:convert';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_photo_storage.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_photo_upload.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_remote_payload.dart';

/// FOTO B: upload -> durable checkpoint -> publish -> conditional acknowledgement.
/// No timers, downloads, signed URLs or cleanup.
class AnimalPhotoSync {
  AnimalPhotoSync(
    this._database,
    this._storage, {
    this.uploadTimeout = const Duration(seconds: 60),
  });
  final Duration uploadTimeout;
  final AppDatabase _database;
  final AnimalPhotoStorage _storage;

  Future<String?> _localOwner() async {
    final session = await _database.readSetting('session');
    return session == null
        ? null
        : (jsonDecode(session) as Map)['id'] as String?;
  }

  Future<void> discoverLocalPhotos() => _database.runInTransaction(() async {
    for (final payload in await _database.readRecords('animals')) {
      final localPath = AnimalPhotoUpload.localPath(payload);
      // A remote-only reference or a future downloaded cache is not an upload.
      if (localPath == null ||
          payload['remotePhotoPath'] != null ||
          AnimalPhotoUpload.read(payload) != null) {
        continue;
      }
      await _database.putRecord(
        'animals',
        payload['id']! as String,
        {
          ...payload,
          AnimalPhotoUpload.key: AnimalPhotoUpload.create(
            localPath,
            SyncMetadata.owner(payload),
          ),
          'syncStatus': 'pending',
        },
        DateTime.parse(payload['updatedAt']! as String),
      );
    }
  });

  Future<bool> push(
    PendingRecord initial,
    Future<void> Function(PendingRecord) publish,
  ) async {
    if (initial.isDeleted) return false;
    final claimed = await _database.beginRemotePublish(initial);
    if (claimed == null) return false;
    final latest = await _database.readRecord(
      initial.collection,
      initial.id,
      includeDeleted: true,
    );
    if (latest == null ||
        latest.isDeleted ||
        !SyncMetadata.sameOperation(latest.payload, claimed.payload) ||
        latest.updatedAt != claimed.updatedAt) {
      return false;
    }
    var record = latest;
    Future<void> confirmPresence() async {
      final owner = record.ownerId;
      if (owner == null || _storage.currentUserId != owner) {
        throw const PhotoUploadFailure('auth_required');
      }
      await _database.markRemoteConfirmed(record.collection, record.id, owner);
    }

    var job = AnimalPhotoUpload.read(record.payload);
    if (job == null) {
      await publish(record);
      await confirmPresence();
      return _database.replaceRecordIfUnchanged(record, {
        ...record.payload,
        'syncStatus': 'synced',
      }, pending: false);
    }

    Future<bool> checkpoint(
      Map<String, Object?> nextJob, {
      String? remotePath,
    }) async {
      final payload = {
        ...record.payload,
        AnimalPhotoUpload.key: nextJob,
        if (remotePath != null) 'remotePhotoPath': remotePath,
      };
      final changed = await _database.replaceRecordIfUnchanged(
        record,
        payload,
        pending: true,
      );
      if (changed) {
        record = PendingRecord(
          collection: record.collection,
          id: record.id,
          payload: payload,
          updatedAt: record.updatedAt,
        );
        job = nextJob;
      }
      return changed;
    }

    Future<String> requireOwner() async {
      final localOwner = await _localOwner();
      final owner = job!['ownerId'] as String? ?? localOwner;
      if (owner == null ||
          localOwner != owner ||
          _storage.currentUserId != owner) {
        throw const PhotoUploadFailure('auth_required');
      }
      return owner;
    }

    try {
      final owner = await requireOwner();
      if (job!['ownerId'] == null) {
        if (!await checkpoint({...job!, 'ownerId': owner})) return false;
      }
      if (job!['status'] != 'uploaded' && job!['status'] != 'published') {
        final file = File(job!['localPath']! as String);
        if (!await file.exists()) {
          throw const PhotoUploadFailure('missing_file');
        }
        // The picker already reduces images. Bound the standard upload's memory.
        if (await file.length() > 6 * 1024 * 1024) {
          throw const PhotoUploadFailure('file_too_large');
        }
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty || bytes.length > 6 * 1024 * 1024) {
          throw const PhotoUploadFailure('invalid_size');
        }
        final contentType = lookupMimeType(file.path, headerBytes: bytes);
        if (contentType == null || !contentType.startsWith('image/')) {
          throw const PhotoUploadFailure('unsupported_image');
        }
        final digest = sha256.convert(bytes).toString();
        if (job!['sha256'] != null && job!['sha256'] != digest) {
          throw const PhotoUploadFailure('local_file_changed');
        }
        final target =
            job!['target'] as String? ??
            '$owner/${record.id}/${job!['version']}.${job!['extension']}';
        AnimalRemotePayload.validatedPhotoPath(target, owner, record.id);
        if (!await checkpoint({
          ...job!,
          'target': target,
          'sha256': digest,
          'contentType': contentType,
          'status': 'pending',
          'lastError': null,
        })) {
          return false;
        }
        await requireOwner();
        await _storage
            .ensureUploaded(
              ownerId: owner,
              objectPath: target,
              bytes: bytes,
              digest: digest,
              contentType: contentType,
            )
            .timeout(uploadTimeout);
        await requireOwner();
        if (!await checkpoint({
          ...job!,
          'status': 'uploaded',
          'lastError': null,
        }, remotePath: target)) {
          return false;
        }
      }
      await requireOwner();
      await publish(record);
      await requireOwner();
      await confirmPresence();
      return _database.replaceRecordIfUnchanged(record, {
        ...record.payload,
        'syncStatus': 'synced',
        AnimalPhotoUpload.key: {
          ...job!,
          'status': 'published',
          'lastError': null,
        },
      }, pending: false);
    } catch (error) {
      // No raw SDK error text: it may contain signed/session data or device paths.
      await checkpoint({
        ...job!,
        'lastError': error is PhotoUploadFailure
            ? error.code
            : 'upload_or_sync_failed',
      });
      rethrow;
    }
  }
}

class PhotoUploadFailure implements Exception {
  const PhotoUploadFailure(this.code);
  final String code;
}
