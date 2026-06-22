import 'dart:convert';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/farm/data/models/farm_model.dart';
import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';

class FarmLocalDataSource {
  const FarmLocalDataSource(this._database);
  final AppDatabase _database;
  Future<Farm?> read() async {
    final raw = await _database.readSetting('farm');
    return raw == null
        ? null
        : FarmModel.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
  }

  Future<void> write(Farm farm) =>
      _database.writeSetting('farm', jsonEncode(FarmModel.toJson(farm)));
}
