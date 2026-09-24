import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/network/network_status.dart';

class Monitor implements NetworkMonitor {
  final initial = Completer<bool>();
  final events = StreamController<bool>.broadcast();
  @override
  Future<bool> check() => initial.future;
  @override
  Stream<bool> get changes => events.stream;
}

void main() {
  test(
    'connection changes and manual offline both gate photo networking',
    () async {
      final monitor = Monitor();
      final container = ProviderContainer(
        overrides: [networkMonitorProvider.overrideWithValue(monitor)],
      );
      final sub = container.listen(photoNetworkAllowedProvider, (_, _) {});
      monitor.initial.complete(false);
      await container.read(networkStatusProvider.future);
      expect(container.read(photoNetworkAllowedProvider), false);
      monitor.events.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(photoNetworkAllowedProvider), true);
      container.read(manualOfflineProvider.notifier).set(true);
      expect(container.read(photoNetworkAllowedProvider), false);
      monitor.events.add(false);
      await Future<void>.delayed(Duration.zero);
      container.read(manualOfflineProvider.notifier).set(false);
      expect(container.read(photoNetworkAllowedProvider), false);
      sub.close();
      container.dispose();
      await monitor.events.close();
    },
  );
  test(
    'late startup check cannot override a newer connectivity event',
    () async {
      final monitor = Monitor();
      final container = ProviderContainer(
        overrides: [networkMonitorProvider.overrideWithValue(monitor)],
      );
      final sub = container.listen(networkStatusProvider, (_, _) {});
      monitor.events.add(false);
      expect(await container.read(networkStatusProvider.future), false);
      monitor.initial.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(networkStatusProvider).requireValue, false);
      sub.close();
      container.dispose();
      await monitor.events.close();
    },
  );
}
