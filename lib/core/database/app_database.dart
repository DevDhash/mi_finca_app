import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// A small schema-less Drift store. Domain repositories own serialization,
/// which keeps the UI independent from both SQLite and a future REST backend.
final class AppDatabase extends GeneratedDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'mi_finca_mvp'));

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo> get allTables => const [];

  final _recordChanges = StreamController<void>.broadcast();
  Stream<void> get recordChanges => _recordChanges.stream;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await customStatement('''
            CREATE TABLE records (
              collection TEXT NOT NULL,
              id TEXT NOT NULL,
              payload TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              pending INTEGER NOT NULL DEFAULT 1,
              PRIMARY KEY (collection, id)
            )
          ''');
      await customStatement('''
            CREATE TABLE settings (
              key TEXT PRIMARY KEY NOT NULL,
              value TEXT NOT NULL
            )
          ''');
    },
  );

  Future<List<Map<String, Object?>>> readRecords(String collection) async {
    final rows = await customSelect(
      'SELECT payload FROM records WHERE collection = ? ORDER BY updated_at DESC',
      variables: [Variable.withString(collection)],
    ).get();

    return rows
        .map(
          (row) => Map<String, Object?>.from(
            jsonDecode(row.read<String>('payload')) as Map,
          ),
        )
        .toList();
  }

  Future<List<PendingRecord>> readPendingRecords() async {
    final rows = await customSelect('''
      SELECT collection, id, payload, updated_at
      FROM records
      WHERE pending = 1
      ORDER BY updated_at ASC
      ''').get();

    return rows
        .map(
          (row) => PendingRecord(
            collection: row.read<String>('collection'),
            id: row.read<String>('id'),
            payload: Map<String, Object?>.from(
              jsonDecode(row.read<String>('payload')) as Map,
            ),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('updated_at'),
            ),
          ),
        )
        .toList();
  }

  Future<void> putRecord(
    String collection,
    String id,
    Map<String, Object?> payload,
    DateTime updatedAt, {
    bool pending = true,
  }) async {
    await customStatement(
      'INSERT OR REPLACE INTO records '
      '(collection, id, payload, updated_at, pending) VALUES (?, ?, ?, ?, ?)',
      [
        collection,
        id,
        jsonEncode(payload),
        updatedAt.millisecondsSinceEpoch,
        pending ? 1 : 0,
      ],
    );

    _recordChanges.add(null);
  }

  Future<void> removeRecord(String collection, String id) async {
    await customStatement(
      'DELETE FROM records WHERE collection = ? AND id = ?',
      [collection, id],
    );

    _recordChanges.add(null);
  }

  Future<int> pendingCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS count FROM records WHERE pending = 1',
    ).getSingle();

    return row.read<int>('count');
  }

  Future<void> markRecordSynced(String collection, String id) async {
    await customStatement(
      '''
      UPDATE records
      SET pending = 0
      WHERE collection = ? AND id = ?
      ''',
      [collection, id],
    );

    _recordChanges.add(null);
  }

  Future<void> markAllSynced() async {
    await customStatement('UPDATE records SET pending = 0');
    _recordChanges.add(null);
  }

  Future<String?> readSetting(String key) async {
    final row = await customSelect(
      'SELECT value FROM settings WHERE key = ?',
      variables: [Variable.withString(key)],
    ).getSingleOrNull();

    return row?.read<String>('value');
  }

  Future<void> writeSetting(String key, String value) => customStatement(
    'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
    [key, value],
  );

  Future<void> deleteSetting(String key) =>
      customStatement('DELETE FROM settings WHERE key = ?', [key]);

  Future<void> clearAll() async {
    await transaction(() async {
      await customStatement('DELETE FROM records');
      await customStatement('DELETE FROM settings');
    });

    _recordChanges.add(null);
  }

  @override
  Future<void> close() async {
    await _recordChanges.close();
    await super.close();
  }
}

class PendingRecord {
  const PendingRecord({
    required this.collection,
    required this.id,
    required this.payload,
    required this.updatedAt,
  });

  final String collection;
  final String id;
  final Map<String, Object?> payload;
  final DateTime updatedAt;
}
