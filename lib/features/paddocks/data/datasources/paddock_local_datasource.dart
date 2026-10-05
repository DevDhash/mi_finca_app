import 'dart:convert';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_history_reference.dart';
import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_patch.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/paddocks/data/models/paddock_model.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';

class PaddockLocalDataSource {
  const PaddockLocalDataSource(this._database);

  final AppDatabase _database;
  int get sessionGeneration => _database.sessionGeneration;

  Future<List<Paddock>> getAll() async => (await _database.readRecords(
    'paddocks',
  )).map(PaddockModel.fromJson).toList();

  Future<Map<String, PaddockHistoryReference>> resolveHistory(
    Set<String> ids,
  ) => _database.runInTransaction(() async {
    final owner = await _database.localOwner();
    if (owner == null) throw StateError('Sesión requerida');
    await _database.requireOwner(owner);
    final result = <String, PaddockHistoryReference>{};
    for (final id in ids) {
      final row = await _database.readRecord(
        'paddocks',
        id,
        includeDeleted: true,
      );
      final owned = row?.ownerId == owner;
      final name = owned ? row?.payload['name'] : null;
      result[id] = PaddockHistoryReference(
        id: id,
        name: name is String ? name : null,
        isDeleted: owned && SyncMetadata.isDeleted(row!.payload),
      );
    }
    await _database.requireOwner(owner);
    return result;
  });

  Future<void> save(
    Paddock paddock, {
    bool pending = true,
    String? verifiedRemoteOwner,
  }) {
    return _database.putRecord(
      'paddocks',
      paddock.id,
      PaddockModel.toJson(paddock),
      paddock.updatedAt,
      pending: pending,
      verifiedRemoteOwner: verifiedRemoteOwner,
    );
  }

  Future<void> edit(String id, PaddockPatch patch) async {
    final owner = await _database.localOwner();
    if (owner == null) throw StateError('Sesión requerida');
    await _database.applyPaddockPatch(id, owner, patch);
  }

  Future<Map<String, String>> snapshot(String owner) =>
      _database.runInTransaction(() async {
        await _database.requireOwner(owner);
        return {
          for (final row in await _database.readRecords(
            'paddocks',
            includeDeleted: true,
          ))
            row['id']! as String: jsonEncode(row),
        };
      });

  Future<void> mergeRemote(
    List<Paddock> items,
    String owner,
    Map<String, String> before,
  ) => _database.runInTransaction(() async {
    await _database.requireOwner(owner);
    for (final item in items) {
      final current = await _database.readRecord(
        'paddocks',
        item.id,
        includeDeleted: true,
      );
      if (jsonEncode(current?.payload) != (before[item.id] ?? 'null')) continue;
      await save(item, pending: false, verifiedRemoteOwner: owner);
    }
  });

  Future<void> markSynced(String id) {
    return _database.markRecordSynced('paddocks', id);
  }
}
