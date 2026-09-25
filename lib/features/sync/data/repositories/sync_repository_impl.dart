import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:mi_finca_app/features/animals/data/services/animal_photo_sync.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/domain/repositories/sync_repository.dart';

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
    if (snapshot == null || snapshot.isDeleted) return false;
    if (snapshot.ownerId != null) return snapshot.ownerId == ownerId;
    final photoOwner = (snapshot.payload['_photoUpload'] as Map?)?['ownerId'];
    if (photoOwner != ownerId &&
        !await remote.verifyLegacyOwner(snapshot, ownerId)) {
      return false;
    }
    if (remote.currentUserId != ownerId) return false;
    return _local.adoptVerifiedOwner(snapshot, ownerId);
  }

  Future<void> _pullTombstones() async {
    final remote = _remote;
    if (remote is! DeletionRemoteDataSource) return;
    final owner = await _local.localOwner();
    if (owner == null || remote.currentUserId != owner) {
      throw StateError('La sesión de sincronización cambió.');
    }
    await _local.requireOwner(owner);
    final List<RemoteTombstone> tombstones;
    try {
      tombstones = await remote.fetchTombstones(owner);
    } on PostgrestException catch (error) {
      if (error.code == '42P01' || error.code == 'PGRST205') return;
      rethrow;
    }
    if (remote.currentUserId != owner) throw StateError('La sesión cambió.');
    await _local.mergeTombstones(owner, tombstones);
  }

  Future<void> _push() async {
    await _discoverPhotos();
    final records = await _local.readPendingRecords();
    var syncedCount = 0;
    for (var record in records) {
      try {
        final transport = _remote;
        if (transport is DeletionRemoteDataSource) {
          final owner = await _local.localOwner();
          if (owner == null || transport.currentUserId != owner) continue;
          await _local.requireOwner(owner);
          if (record.ownerId == null && !record.isDeleted) {
            // An authenticated existing remote row is evidence; a session alone isn't.
            final photoOwner =
                (record.payload['_photoUpload'] as Map?)?['ownerId'];
            if (photoOwner != owner &&
                !await transport.verifyLegacyOwner(record, owner)) {
              continue;
            }
            if (!await _local.adoptVerifiedOwner(record, owner)) continue;
            record = (await _local.current(record))!;
          }
          if (record.ownerId != owner) continue;
        } else if (record.ownerId != null) {
          await _local.requireOwner(record.ownerId!);
        }
        final current = await _local.current(record);
        if (jsonEncode(current?.payload) != jsonEncode(record.payload)) {
          continue;
        }
        final bool confirmed;
        if (record.isDeleted) {
          if (transport is! DeletionRemoteDataSource) continue;
          final tombstone = await transport.softDelete(record);
          if (transport.currentUserId != record.ownerId) {
            throw StateError('La sesión cambió.');
          }
          confirmed = await _local.acknowledgeDelete(record, tombstone);
        } else if (record.collection == 'animals' && _photos != null) {
          confirmed = await _photos.push(record, _remote.pushRecord);
        } else {
          await _remote.pushRecord(record);
          confirmed = await _local.acknowledge(record);
        }
        if (confirmed) syncedCount++;
      } catch (_) {
        // A direct upsert can have been rejected by the terminal-ID guard.
        // Only an authenticated tombstone resolves it; errors alone never do.
        try {
          await pullRemoteTombstones();
        } catch (_) {
          // Migration/network unavailable: preserve the original pending work.
        }
        // A failed upload/publication stays durable and pending for the next
        // explicit sync or save. Other records can still make progress.
      }
    }
    if (syncedCount > 0) await _local.saveLastSync(DateTime.now());
  }
}
