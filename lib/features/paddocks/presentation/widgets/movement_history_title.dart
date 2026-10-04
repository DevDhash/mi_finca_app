import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_history_reference.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_history_provider.dart';

class MovementHistoryTitle extends ConsumerWidget {
  const MovementHistoryTitle({super.key, required this.movement});
  final Movement movement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String resolve(String id) {
      final state = ref.watch(paddockHistoryProvider(id));
      // Do not display retained data from a previous owner while reloading.
      final reference = !state.isLoading && !state.hasError
          ? state.asData?.value
          : null;
      return (reference ?? PaddockHistoryReference(id: id)).label;
    }

    final from = movement.fromPaddockId;
    return Text(
      '${from == null ? 'Sin potrero de origen' : resolve(from)} → ${resolve(movement.toPaddockId)}',
    );
  }
}
