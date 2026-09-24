import 'package:mi_finca_app/features/animals/data/services/animal_photo_sync.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/domain/repositories/sync_repository.dart';

class SyncRepositoryImpl implements SyncRepository {
  SyncRepositoryImpl(this._local, this._remote, {AnimalPhotoSync? photos})
    : _photos = photos;

  final SyncLocalDataSource _local;
  final SyncRemoteDataSource _remote;
  final AnimalPhotoSync? _photos;
  Future<void>? _active;
  Future<void>? _discovery;

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

  Future<void> _push() async {
    await _discoverPhotos();
    final records = await _local.readPendingRecords();
    var syncedCount = 0;
    for (final record in records) {
      try {
        final bool confirmed;
        if (record.collection == 'animals' && _photos != null) {
          confirmed = await _photos.push(record, _remote.pushRecord);
        } else {
          await _remote.pushRecord(record);
          confirmed = await _local.acknowledge(record);
        }
        if (confirmed) syncedCount++;
      } catch (_) {
        // A failed upload/publication stays durable and pending for the next
        // explicit sync or save. Other records can still make progress.
      }
    }
    if (syncedCount > 0) await _local.saveLastSync(DateTime.now());
  }
}
