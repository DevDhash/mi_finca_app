import 'dart:convert';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/farm/data/models/farm_model.dart';
import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';

class FarmLocalDataSource {
  const FarmLocalDataSource(this._database);
  final AppDatabase _database;

  Future<Farm?> read() async {
    final records = await _database.readRecords('farms');

    if (records.isNotEmpty) {
      return FarmModel.fromJson(records.first);
    }

    if ((await _database.readRecords(
      'farms',
      includeDeleted: true,
    )).isNotEmpty) {
      return null;
    }
    final legacyRaw = await _database.readSetting('farm');
    if (legacyRaw == null) return null;

    return FarmModel.fromJson(
      Map<String, Object?>.from(jsonDecode(legacyRaw) as Map),
    );
  }

  Future<void> write(
    Farm farm, {
    bool pending = true,
    String? verifiedRemoteOwner,
  }) {
    return _database.putRecord(
      'farms',
      farm.id,
      FarmModel.toJson(farm),
      DateTime.now(),
      pending: pending,
      verifiedRemoteOwner: verifiedRemoteOwner,
    );
  }
}
