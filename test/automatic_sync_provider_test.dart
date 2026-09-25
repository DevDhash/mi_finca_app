import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/core/network/network_status.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_photo_url_source.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_photo_provider.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';
import 'package:mi_finca_app/features/sync/data/services/automatic_sync.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/automatic_sync_provider.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';
import 'remote_presence_sync_test.dart' show PresenceRemote;

class SyncMonitor implements NetworkMonitor {
  bool online = true;
  final events = StreamController<bool>.broadcast(sync: true);
  @override
  Future<bool> check() async => online;
  @override
  Stream<bool> get changes => events.stream;
  void emit(bool value) {
    online = value;
    events.add(value);
  }
}

class SyncAuth implements AnimalPhotoUrlSource {
  @override
  String? currentUserId = 'owner';
  final events = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get authChanges => events.stream;
  @override
  Future<String> sign(String a, String b, int c) => throw UnimplementedError();
}

class CountingSync extends SyncViewModel {
  int updates = 0;
  @override
  void setConnectivity(bool online) {
    updates++;
    super.setConnectivity(online);
  }
}

class CountingRepository extends SyncRepositoryImpl {
  CountingRepository(super.local, super.remote);
  int calls = 0;
  int active = 0;
  int maximumActive = 0;
  Completer<void>? gate;
  @override
  Future<void> pushPendingChanges() async {
    calls++;
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      await gate?.future;
      await super.pushPendingChanges();
    } finally {
      active--;
    }
  }
}

class SyncHarness extends ConsumerWidget {
  const SyncHarness({super.key, this.duringBuild});
  final VoidCallback? duringBuild;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    duringBuild?.call();
    // A dirty network provider is flushed here, while Flutter is building.
    ref.watch(networkStatusProvider);
    ref.watch(automaticSyncProvider);
    final state = ref.watch(syncViewModelProvider);
    return Text('${state.value?.isOnline}', textDirection: TextDirection.ltr);
  }
}

void main() {
  late AppDatabase db;
  late SyncMonitor monitor;
  late SyncAuth auth;
  late CountingSync viewModel;
  late PresenceRemote remote;
  late CountingRepository repository;
  late ProviderContainer container;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.writeSetting('session', jsonEncode({'id': 'owner'}));
    monitor = SyncMonitor();
    auth = SyncAuth();
    viewModel = CountingSync();
    remote = PresenceRemote();
    repository = CountingRepository(SyncLocalDataSource(db), remote);
    container = ProviderContainer(
      overrides: [
        networkMonitorProvider.overrideWithValue(monitor),
        animalPhotoUrlSourceProvider.overrideWithValue(auth),
        syncRepositoryProvider.overrideWithValue(repository),
        syncViewModelProvider.overrideWith(() => viewModel),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await monitor.events.close();
    await auth.events.close();
    await db.close();
  });
  Future<void> mount(WidgetTester tester) async {
    await container.read(syncViewModelProvider.future);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SyncHarness(),
      ),
    );
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  Future<void> pendingDelete() async {
    await db.putRecord('animals', 'animal', {
      'id': 'animal',
      'name': 'Test',
    }, DateTime.utc(2026));
    await db.markRemoteConfirmed('animals', 'animal', 'owner');
    await db.markDeleted('animals', 'animal', 'owner');
  }

  AutomaticSync worker() => container.read(automaticSyncProvider);

  testWidgets(
    'network recomputation during widget rebuild does not mutate another provider in build',
    (tester) async {
      await mount(tester);
      container.invalidate(networkStatusProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SyncHarness(key: ValueKey('rebuild')),
        ),
      );
      await drain(tester);
      expect(tester.takeException(), isNull);
      expect(container.read(syncViewModelProvider).requireValue.isOnline, true);
      expect(worker().enabled, true);
    },
  );
  testWidgets('auth notification during build uses the same safe update path', (
    tester,
  ) async {
    await mount(tester);
    var emitted = false;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: SyncHarness(
          key: const ValueKey('auth'),
          duringBuild: () {
            if (!emitted) {
              emitted = true;
              auth.events.add('owner');
            }
          },
        ),
      ),
    );
    await drain(tester);
    expect(tester.takeException(), isNull);
    expect(worker().enabled, true);
  });
  testWidgets(
    'consecutive signals coalesce and read latest auth/network instead of captured values',
    (tester) async {
      await mount(tester);
      final original = worker();
      final count = viewModel.updates;
      auth.events.add('owner');
      monitor.emit(false);
      auth.events.add('owner');
      monitor.emit(true);
      auth.currentUserId = null;
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(viewModel.updates - count, 1);
      expect(identical(worker(), original), true);
      expect(worker().enabled, false);
      expect(container.read(syncViewModelProvider).requireValue.isOnline, true);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'dispose cancels queued callback before it can mutate SyncViewModel',
    (tester) async {
      await mount(tester);
      final count = viewModel.updates;
      auth.events.add('owner');
      container.invalidate(automaticSyncProvider);
      // Remove the consumer before the pending update gets its event-loop turn.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      expect(viewModel.updates, count);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'offline to online enables worker and ACKs a confirmed pending DELETE',
    (tester) async {
      monitor.online = false;
      await pendingDelete();
      await mount(tester);
      await drain(tester);
      expect(worker().enabled, false);
      expect(remote.ledger, isEmpty);
      monitor.emit(true);
      await drain(tester);
      expect(container.read(syncViewModelProvider).requireValue.isOnline, true);
      expect(worker().enabled, true);
      expect(remote.ledger, hasLength(1));
      expect(await db.pendingCount(), 0);
      final row = (await db.readRecord(
        'animals',
        'animal',
        includeDeleted: true,
      ))!;
      expect(row.isDeleted, true);
      expect(row.remotePresence, RemotePresence.confirmed);
      expect(
        SyncMetadata.read(row.payload)['remoteOperationId'],
        remote.ledger.single.operationId,
      );
    },
  );
  testWidgets(
    'DELETE created already online is processed from outbox without another network event',
    (tester) async {
      await mount(tester);
      await drain(tester);
      expect(repository.calls, 0);
      await pendingDelete();
      final operation = (await db.readPendingRecords()).single;
      expect(operation.operation, 'delete');
      expect(operation.remotePresence, RemotePresence.confirmed);
      await drain(tester);
      expect(remote.ledger, hasLength(1));
      expect(remote.ledger.single.operationId, operation.operationId);
      expect(await db.pendingCount(), 0);
      expect(repository.maximumActive, 1);
    },
  );
  testWidgets(
    'resume invalidation and rebuild converge without Riverpod assertion',
    (tester) async {
      await mount(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(Duration.zero);
      expect(worker().enabled, false);
      await container.read(syncViewModelProvider.future);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SyncHarness(key: ValueKey('resume')),
        ),
      );
      await drain(tester);
      expect(tester.takeException(), isNull);
      expect(worker().enabled, true);
      expect(container.read(syncViewModelProvider).requireValue.isOnline, true);
    },
  );
  testWidgets('online to offline disables worker and leaves DELETE pending', (
    tester,
  ) async {
    await mount(tester);
    monitor.emit(false);
    await drain(tester);
    expect(worker().enabled, false);
    expect(container.read(syncViewModelProvider).requireValue.isOnline, false);
    await pendingDelete();
    await drain(tester);
    expect(remote.ledger, isEmpty);
    expect(await db.pendingCount(), 1);
  });
  testWidgets(
    'repeated auth network and outbox events do not duplicate running sync or busy loop',
    (tester) async {
      await mount(tester);
      await drain(tester);
      repository.gate = Completer<void>();
      await pendingDelete();
      await drain(tester);
      expect(repository.calls, 1);
      for (var i = 0; i < 5; i++) {
        auth.events.add('owner');
        monitor.emit(true);
      }
      await drain(tester);
      expect(repository.calls, 1);
      repository.gate!.complete();
      await drain(tester);
      await tester.pump(const Duration(minutes: 6));
      expect(repository.maximumActive, 1);
      expect(repository.calls, 1);
      expect(remote.ledger, hasLength(1));
      expect(await db.pendingCount(), 0);
      expect(tester.takeException(), isNull);
    },
  );
}
