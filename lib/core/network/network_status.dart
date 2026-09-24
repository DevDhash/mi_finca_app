import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class NetworkMonitor {
  Future<bool> check();
  Stream<bool> get changes;
}

class DeviceNetworkMonitor implements NetworkMonitor {
  final Connectivity _connectivity = Connectivity();
  bool _available(List<ConnectivityResult> values) =>
      values.any((value) => value != ConnectivityResult.none);
  @override
  Future<bool> check() async =>
      _available(await _connectivity.checkConnectivity());
  @override
  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map(_available).distinct();
}

final networkMonitorProvider = Provider<NetworkMonitor>(
  (ref) => DeviceNetworkMonitor(),
);

final networkStatusProvider = StreamProvider<bool>((ref) {
  final monitor = ref.watch(networkMonitorProvider);
  final controller = StreamController<bool>();
  var receivedEvent = false;
  final subscription = monitor.changes.listen((online) {
    receivedEvent = true;
    controller.add(online);
  }, onError: (_) => controller.add(true));
  unawaited(
    monitor
        .check()
        .then((online) {
          if (!receivedEvent && !controller.isClosed) controller.add(online);
        })
        .catchError((_) {
          if (!controller.isClosed) controller.add(true);
        }),
  );
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
});

class ManualOffline extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final manualOfflineProvider = NotifierProvider<ManualOffline, bool>(
  ManualOffline.new,
);
final photoNetworkAllowedProvider = Provider<bool>((ref) {
  // Keep observing connectivity while the manual switch is off, so disabling
  // that switch cannot momentarily reuse a stale online snapshot.
  final network = ref.watch(networkStatusProvider).asData?.value ?? true;
  final manualOffline = ref.watch(manualOfflineProvider);
  return network && !manualOffline;
});
