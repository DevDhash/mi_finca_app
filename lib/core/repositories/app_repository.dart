import 'dart:convert';

import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/models/app_models.dart';

abstract interface class AppRepository {
  Future<UserSession?> session();
  Future<void> saveSession(UserSession value);
  Future<void> signOut();
  Future<Farm?> farm();
  Future<void> saveFarm(Farm value);
  Future<List<Animal>> animals();
  Future<void> saveAnimal(Animal value);
  Future<List<Paddock>> paddocks();
  Future<void> savePaddock(Paddock value);
  Future<List<Expense>> expenses();
  Future<void> saveExpense(Expense value);
  Future<List<Movement>> movements();
  Future<void> saveMovement(Movement value);
  Future<int> pendingCount();
  Future<void> markAllSynced();
  Future<DateTime?> lastSync();
  Future<void> clearAll();
}

class LocalAppRepository implements AppRepository {
  LocalAppRepository(this._db);
  final AppDatabase _db;

  @override
  Future<UserSession?> session() async {
    final raw = await _db.readSetting('session');
    return raw == null
        ? null
        : UserSession.fromJson(
            Map<String, Object?>.from(jsonDecode(raw) as Map),
          );
  }

  @override
  Future<void> saveSession(UserSession value) =>
      _db.writeSetting('session', jsonEncode(value.toJson()));
  @override
  Future<void> signOut() => _db.deleteSetting('session');
  @override
  Future<Farm?> farm() async {
    final raw = await _db.readSetting('farm');
    return raw == null
        ? null
        : Farm.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
  }

  @override
  Future<void> saveFarm(Farm value) =>
      _db.writeSetting('farm', jsonEncode(value.toJson()));
  @override
  Future<List<Animal>> animals() async =>
      (await _db.readRecords('animals')).map(Animal.fromJson).toList();
  @override
  Future<void> saveAnimal(Animal value) =>
      _db.putRecord('animals', value.id, value.toJson(), value.updatedAt);
  @override
  Future<List<Paddock>> paddocks() async =>
      (await _db.readRecords('paddocks')).map(Paddock.fromJson).toList();
  @override
  Future<void> savePaddock(Paddock value) =>
      _db.putRecord('paddocks', value.id, value.toJson(), value.updatedAt);
  @override
  Future<List<Expense>> expenses() async =>
      (await _db.readRecords('expenses')).map(Expense.fromJson).toList();
  @override
  Future<void> saveExpense(Expense value) =>
      _db.putRecord('expenses', value.id, value.toJson(), value.updatedAt);
  @override
  Future<List<Movement>> movements() async =>
      (await _db.readRecords('movements')).map(Movement.fromJson).toList();
  @override
  Future<void> saveMovement(Movement value) =>
      _db.putRecord('movements', value.id, value.toJson(), value.date);
  @override
  Future<int> pendingCount() => _db.pendingCount();
  @override
  Future<void> markAllSynced() async {
    await _db.markAllSynced();
    await _db.writeSetting('last_sync', DateTime.now().toIso8601String());
  }

  @override
  Future<DateTime?> lastSync() async {
    final raw = await _db.readSetting('last_sync');
    return raw == null ? null : DateTime.parse(raw);
  }

  @override
  Future<void> clearAll() => _db.clearAll();
}

/// Contract for the future API. Replace this mock with an HTTP implementation
/// and keep [AppController] and every screen unchanged.
abstract interface class RemoteGateway {
  Future<void> pushChanges();
}

class MockRemoteGateway implements RemoteGateway {
  @override
  Future<void> pushChanges() =>
      Future<void>.delayed(const Duration(milliseconds: 900));
}
