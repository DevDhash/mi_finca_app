import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';

abstract interface class FarmRepository {
  Future<Farm?> getFarm();
  Future<void> saveFarm(Farm farm);
}
