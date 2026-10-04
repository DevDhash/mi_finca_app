import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_history_reference.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';

/// SQLite-only history, separate from the operational Paddock list.
final paddockHistoryProvider = StreamProvider.autoDispose
    .family<PaddockHistoryReference, String>((ref, id) {
      final owner = ref.watch(
        authViewModelProvider.select((s) => s.asData?.value?.id),
      );
      if (owner == null) {
        return Stream.value(PaddockHistoryReference(id: id));
      }
      final database = ref.watch(databaseProvider);
      final local = ref.watch(paddockLocalDataSourceProvider);
      final changes = StreamController<void>();
      // Subscribe before the first read so no intervening tombstone is missed.
      final subscription = database.recordChanges.listen(
        (_) => changes.add(null),
      );
      changes.add(null);
      ref.onDispose(() {
        subscription.cancel();
        changes.close();
      });
      return changes.stream.asyncMap((_) async {
        if (await database.localOwner() != owner) {
          return PaddockHistoryReference(id: id);
        }
        final references = await local.resolveHistory({id});
        if (await database.localOwner() != owner) {
          return PaddockHistoryReference(id: id);
        }
        return references[id]!;
      });
    });
