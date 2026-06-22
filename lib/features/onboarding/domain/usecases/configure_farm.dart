import 'package:mi_finca_app/features/farm/domain/repositories/farm_repository.dart';
import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/repositories/paddock_repository.dart';
import 'package:uuid/uuid.dart';

class ConfigureFarm {
  const ConfigureFarm(this._farmRepository, this._paddockRepository);
  final FarmRepository _farmRepository;
  final PaddockRepository _paddockRepository;

  Future<Farm> call(String name, String location, String firstPaddock) async {
    final farm = Farm(
      id: const Uuid().v4(),
      name: name.trim(),
      location: location.trim(),
    );
    await _farmRepository.saveFarm(farm);
    if (firstPaddock.trim().isNotEmpty) {
      final now = DateTime.now();
      await _paddockRepository.save(
        Paddock(
          id: const Uuid().v4(),
          name: firstPaddock.trim(),
          areaHectares: 1,
          grassType: 'Por definir',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    return farm;
  }
}
