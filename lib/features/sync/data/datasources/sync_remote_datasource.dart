import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';

abstract interface class SyncRemoteDataSource {
  Future<void> pushRecord(PendingRecord record);
}

/// Optional capability: existing test/mock upsert transports remain unchanged.
abstract interface class DeletionRemoteDataSource
    implements SyncRemoteDataSource {
  String? get currentUserId;
  Future<RemoteTombstone> softDelete(PendingRecord record);
  Future<List<RemoteTombstone>> fetchTombstones(String ownerId);
  Future<bool> verifyLegacyOwner(PendingRecord record, String ownerId);
}
