import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_history_reference.dart';
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

/// Separate read-only capability; never feeds operational lists.
abstract interface class PaddockHistoryRepository {
  Future<Map<String, PaddockHistoryReference>> resolveHistory(Set<String> ids);
}

abstract interface class PaddockRefreshRepository {
  Future<List<Paddock>> refreshPaddocks();
  Future<List<Paddock>> getLocal();
}
