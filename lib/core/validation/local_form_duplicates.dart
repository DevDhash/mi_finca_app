import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'dart:async';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';

const animalDuplicateMessage = 'Este animal ya existe. Utiliza otro código';
const paddockDuplicateMessage = 'Este potrero ya existe. Utiliza otro nombre';

/// Read-only form candidates, including pending writes, scoped to the local owner.
final localFormRecordsProvider = StreamProvider.autoDispose
    .family<List<Map<String, Object?>>, String>((ref, collection) {
      ref.watch(
        authViewModelProvider.select((value) => value.asData?.value?.id),
      );
      final db = ref.watch(databaseProvider);
      Future<List<Map<String, Object?>>> read() =>
          db.runInTransaction(() async {
            final owner = await db.localOwner();
            if (owner == null) return <Map<String, Object?>>[];
            return (await db.readRecords(
              collection,
            )).where((record) => SyncMetadata.owner(record) == owner).toList();
          });
      // Subscribe before the initial read so changes during it are not lost.
      final changes = StreamController<void>();
      final subscription = db.recordChanges.listen((_) => changes.add(null));
      changes.add(null);
      ref.onDispose(() {
        subscription.cancel();
        changes.close();
      });
      return changes.stream.asyncMap((_) => read());
    });

bool hasLocalFormDuplicate(
  Iterable<Map<String, Object?>> records,
  String value, {
  required String field,
  String? excludingId,
  bool ignoreCase = false,
}) {
  String normalize(String text) =>
      ignoreCase ? text.trim().toLowerCase() : text.trim();
  final candidate = normalize(value);
  if (candidate.isEmpty) return false;
  return records.any(
    (record) =>
        record['id'] != excludingId &&
        !SyncMetadata.isDeleted(record) &&
        record[field] is String &&
        normalize(record[field]! as String) == candidate,
  );
}
