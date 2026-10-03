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

abstract interface class PaddockPatchRemoteDataSource
    implements DeletionRemoteDataSource {
  Future<String?> paddockVersion(String id, String owner);
  Future<void> pushPaddockPatch(PendingRecord command);
}

abstract interface class AnimalPatchRemoteDataSource
    implements DeletionRemoteDataSource {
  Future<String?> animalVersion(String id, String owner);
  Future<void> pushAnimalPatch(PendingRecord command);
}

abstract interface class AnimalMoveRemoteDataSource
    implements DeletionRemoteDataSource {
  Future<Map<String, Object?>> pushAnimalMove(PendingRecord command);
  Future<Map<String, Object?>> readAnimalMoveState(PendingRecord command);
}

abstract interface class PaddockReconciliationRemoteDataSource
    implements DeletionRemoteDataSource {
  Future<Map<String, Object?>?> readActivePaddock(String id, String owner);
}
