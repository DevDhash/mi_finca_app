import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_local_datasource.dart';
import 'package:mi_finca_app/features/paddocks/domain/repositories/paddock_repository.dart';

class PaddockRepositoryImpl implements PaddockRepository {
  const PaddockRepositoryImpl(this._local);
  final PaddockLocalDataSource _local;
  @override
  Future<List<Paddock>> getAll() => _local.getAll();
  @override
  Future<void> save(Paddock paddock) => _local.save(paddock);
}
