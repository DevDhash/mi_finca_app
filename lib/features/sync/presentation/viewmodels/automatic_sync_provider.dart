import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/network/network_status.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_photo_provider.dart';
import 'package:mi_finca_app/features/sync/data/services/automatic_sync.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';

final automaticSyncProvider = Provider.autoDispose<AutomaticSync>((ref) {
  final repository = ref.watch(syncRepositoryProvider);
  final auth = ref.watch(animalPhotoUrlSourceProvider);
  var foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  final worker = AutomaticSync(
    sync: () => ref.read(syncViewModelProvider.notifier).syncPendingIfOnline(),
    pendingCount: repository.pendingCount,
    changes: repository.changes,
  );
  void update() {
    if (!ref.mounted) return;
    final network = ref.read(networkStatusProvider).asData?.value ?? true;
    ref.read(syncViewModelProvider.notifier).setConnectivity(network);
    worker.setEnabled(
      foreground &&
          network &&
          !ref.read(manualOfflineProvider) &&
          auth.currentUserId != null,
    );
  }

  ref.listen(networkStatusProvider, (_, _) => update());
  ref.listen(manualOfflineProvider, (_, _) => update());
  final authSubscription = auth.authChanges.listen((_) {
    update();
    worker.trigger(resetBackoff: true);
  });
  final lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      foreground = state == AppLifecycleState.resumed;
      update();
      if (foreground) {
        ref.invalidate(networkStatusProvider);
        worker.trigger(resetBackoff: true);
      }
    },
  );
  // Delay state changes until after the build that starts the worker.
  scheduleMicrotask(update);
  ref.onDispose(() {
    worker.dispose();
    lifecycle.dispose();
    unawaited(authSubscription.cancel());
  });
  return worker;
});
