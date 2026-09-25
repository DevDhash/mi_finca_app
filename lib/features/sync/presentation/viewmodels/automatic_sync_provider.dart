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
  Timer? scheduledUpdate;
  var resetBackoff = false;

  void update() {
    if (!ref.mounted) return;
    final network = ref.read(networkStatusProvider).asData?.value ?? true;
    ref.read(syncViewModelProvider.notifier).setConnectivity(network);
    worker.setEnabled(
      foreground &&
          network &&
          !ref.read(manualOfflineProvider) &&
          ref.read(animalPhotoUrlSourceProvider).currentUserId != null,
    );
    if (resetBackoff) {
      resetBackoff = false;
      worker.trigger(resetBackoff: true);
    }
  }

  // Listeners may run while Flutter/Riverpod is flushing a build. A zero-time
  // timer crosses that synchronous boundary; it is not a time-based delay.
  // Keep one callback per burst and read live inputs only when it executes.
  void scheduleUpdate({bool reset = false}) {
    if (!ref.mounted) return;
    resetBackoff |= reset;
    scheduledUpdate ??= Timer(Duration.zero, () {
      scheduledUpdate = null;
      if (!ref.mounted) return;
      update();
    });
  }

  ref.listen(networkStatusProvider, (_, _) => scheduleUpdate());
  ref.listen(manualOfflineProvider, (_, _) => scheduleUpdate());
  final authSubscription = auth.authChanges.listen((_) {
    scheduleUpdate(reset: true);
  });
  final lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      foreground = state == AppLifecycleState.resumed;
      scheduleUpdate(reset: foreground);
      if (foreground) {
        ref.invalidate(networkStatusProvider);
      }
    },
  );
  scheduleUpdate();
  ref.onDispose(() {
    scheduledUpdate?.cancel();
    worker.dispose();
    lifecycle.dispose();
    unawaited(authSubscription.cancel());
  });
  return worker;
});
