import 'package:mi_finca_app/features/farm/domain/repositories/farm_repository.dart';
import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';
import 'package:uuid/uuid.dart';

class ConfigureFarm {
  const ConfigureFarm(this._farmRepository);
  final FarmRepository _farmRepository;

  Future<Farm> call(String name, String location) async {
    final farm = Farm(
      id: const Uuid().v4(),
      name: name.trim(),
      location: location.trim(),
    );
    await _farmRepository.saveFarm(farm);
    return farm;
  }
}
