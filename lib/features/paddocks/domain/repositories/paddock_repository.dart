import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_patch.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';

abstract interface class PaddockRepository {
  Future<List<Paddock>> getAll();
  Future<void> save(Paddock paddock);
}

/// Optional capability keeps legacy/test repositories explicit; no snapshot fallback.
abstract interface class PaddockEditRepository {
  Future<void> edit(String id, PaddockPatch patch);
}
