import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';

abstract interface class PaddockRepository {
  Future<List<Paddock>> getAll();
  Future<void> save(Paddock paddock);
}
