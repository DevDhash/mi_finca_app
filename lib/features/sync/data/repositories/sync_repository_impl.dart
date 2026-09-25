import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    final readRemotely = photoOwner != ownerId;
    if (readRemotely && !await remote.verifyLegacyOwner(snapshot, ownerId)) {
      return false;
    }
    if (remote.currentUserId != ownerId) return false;
    final adopted = await _local.adoptVerifiedOwner(snapshot, ownerId);
    if (readRemotely) await _local.markRemoteConfirmed(collection, id, ownerId);
    return adopted;
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
    final attempted = <String>{};
    final checkedParents = <String, bool>{};
    String key(PendingRecord r) => '${r.collection}/${r.id}';
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
      if (parent?.ownerId != null && parent!.ownerId != owner) return false;
      if (parent?.remotePresence == RemotePresence.confirmed) return true;
      // A refresh or another operation may have confirmed this parent since
      // a previous sibling deferred. Durable evidence wins over negative cache.
      final cached = checkedParents[parentKey];
      if (cached != null) return cached;
      // Also memoize failed reads for this pass; siblings must not flood a
      // failing endpoint. A new sync pass gets a fresh reconciliation attempt.
      checkedParents[parentKey] = false;
      if (parent == null || parent.remotePresence == RemotePresence.unknown) {
        // Positive row lookup includes soft-deleted parents. Missing/RLS/error
        // never proves absence, and a ledger entry isn't physical-row evidence.
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
      // At most one attempt per identity per pass. Do not publish a terminal
      // parent merely to satisfy its child, and never busy-loop on failures.
      if (parent != null && !parent.isDeleted) {
        final candidates = await _local.readPendingRecords();
        final pending = candidates
            .where((r) => r.collection == collection && r.id == id)
            .firstOrNull;
        if (pending != null) await process(pending);
      }
      parent = await _local.find(collection, id);
      final ready =
          parent?.ownerId == owner &&
          parent?.remotePresence == RemotePresence.confirmed;
      checkedParents[parentKey] = ready;
      return ready;
    }

    Future<bool> dependenciesReady(PendingRecord record) async {
      if (record.collection != 'movements' || record.isDeleted) return true;
      final owner = record.ownerId;
      if (owner == null) return false;
      // Paddocks first also helps the animal's own paddock reference.
      final paddocks = {
        record.payload['fromPaddockId'],
        record.payload['toPaddockId'],
      }.whereType<String>().toSet();
      for (final id in paddocks) {
        if (!await parentReady('paddocks', id, owner)) return false;
      }
      final animalId = record.payload['animalId'];
      return animalId is String &&
          await parentReady('animals', animalId, owner);
    }

    process = (initial) async {
      if (!attempted.add(key(initial))) return;
      var record = initial;
      try {
        final transport = _remote;
        if (transport is DeletionRemoteDataSource) {
          final owner = await _local.localOwner();
          if (owner == null || transport.currentUserId != owner) return;
          await _local.requireOwner(owner);
          if (record.ownerId == null && !record.isDeleted) {
            final photoOwner =
                (record.payload['_photoUpload'] as Map?)?['ownerId'];
            final readRemotely = photoOwner != owner;
            if (readRemotely &&
                !await transport.verifyLegacyOwner(record, owner)) {
              return;
            }
            if (transport.currentUserId != owner) return;
            if (!await _local.adoptVerifiedOwner(record, owner)) return;
            if (readRemotely) {
              await _local.markRemoteConfirmed(
                record.collection,
                record.id,
                owner,
              );
            }
            record = (await _local.current(record))!;
          }
          if (record.ownerId != owner) return;
        } else if (record.ownerId != null) {
          await _local.requireOwner(record.ownerId!);
        }
        if (!await dependenciesReady(record)) return;
        final current = await _local.current(record);
        if (current == null ||
            !SyncMetadata.sameOperation(current.payload, record.payload)) {
          return;
        }
        record = current;
        final bool confirmed;
        if (record.isDeleted) {
          if (transport is! DeletionRemoteDataSource) return;
          final tombstone = await transport.softDelete(record);
          if (transport.currentUserId != record.ownerId) {
            throw StateError('La sesión cambió.');
          }
          confirmed = await _local.acknowledgeDelete(record, tombstone);
        } else if (record.collection == 'animals' && _photos != null) {
          confirmed = await _photos.push(record, _remote.pushRecord);
        } else {
          final claimed = await _local.beginRemotePublish(record);
          if (claimed == null) return;
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
        if (confirmed) syncedCount++;
      } catch (_) {
        try {
          await pullRemoteTombstones();
        } catch (_) {
          // Preserve pending operations if reconciliation isn't available.
        }
      }
    };
    for (final record in records) {
      await process(record);
    }
    if (syncedCount > 0) await _local.saveLastSync(DateTime.now());
  }
}
