import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/sync/data/services/automatic_sync.dart';

void main() {
  testWidgets(
    'retries with backoff, stops offline, resumes without duplicate worker',
    (tester) async {
      final changes = StreamController<void>.broadcast(sync: true);
      var calls = 0;
      var pending = 1;
      final worker = AutomaticSync(
        changes: changes.stream,
        debounce: const Duration(milliseconds: 1),
        delays: const [Duration(seconds: 5), Duration(seconds: 15)],
        pendingCount: () async => pending,
        sync: () async {
          calls++;
          changes.add(null);
        },
      );
      worker.setEnabled(true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 1);
      changes.add(null);
      await tester.pump(const Duration(seconds: 4));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
      worker.setEnabled(false);
      await tester.pump(const Duration(minutes: 1));
      expect(calls, 2);
      pending = 0;
      worker.setEnabled(true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 2);
      pending = 1;
      changes.add(null);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 3);
      worker.dispose();
      await changes.close();
      await tester.pump(const Duration(minutes: 1));
      expect(calls, 3);
    },
  );
  testWidgets('failed attempt retries and success cancels further retries', (
    tester,
  ) async {
    final changes = StreamController<void>.broadcast();
    var calls = 0;
    var pending = 1;
    final worker = AutomaticSync(
      changes: changes.stream,
      debounce: Duration.zero,
      delays: const [Duration(seconds: 5)],
      pendingCount: () async => pending,
      sync: () async {
        if (++calls == 1) throw StateError('network');
        pending = 0;
      },
    );
    worker.setEnabled(true);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 2);
    await tester.pump(const Duration(minutes: 10));
    expect(calls, 2);
    worker.dispose();
    await changes.close();
  });
}
