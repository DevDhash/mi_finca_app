// Run with: flutter run -d chrome -t tool/check_web_database.dart
// Uses a separate database; never accesses the user's farm or Supabase.
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';

AppDatabase openSmokeDatabase() => AppDatabase(
  driftDatabase(
    name: 'mi_finca_web_smoke',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  ),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) {
        final db = openSmokeDatabase();
        ref.onDispose(db.close);
        return db;
      }),
    ],
  );
  String message;
  try {
    final db = container.read(databaseProvider);
    final previous = await db.readSetting('smoke_runs');
    final run = int.parse(previous ?? '0') + 1;
    await db.writeSetting('smoke_runs', '$run');
    await db.putRecord('smoke', 'record', {
      'id': 'record',
      'run': run,
    }, DateTime.now());
    if ((await db.readRecord('smoke', 'record'))?.payload['run'] != run) {
      throw StateError('Record read failed');
    }
    await db.close();
    final reopened = openSmokeDatabase();
    try {
      if (await reopened.readSetting('smoke_runs') != '$run' ||
          (await reopened.readRecord('smoke', 'record'))?.payload['run'] !=
              run) {
        throw StateError('Persistence after reopen failed');
      }
    } finally {
      await reopened.close();
    }
    message =
        'WEB DATABASE PASS: write/read/reopen. Previous runs: ${previous ?? "0"}. Reload to verify persistence across page loads.';
  } catch (error, stack) {
    message = 'WEB DATABASE FAIL: $error\n$stack';
  }
  // Keep the container alive for the page lifetime (the database is closed).
  debugPrint(message);
  runApp(
    MaterialApp(
      home: Scaffold(body: Center(child: Text(message))),
    ),
  );
}
