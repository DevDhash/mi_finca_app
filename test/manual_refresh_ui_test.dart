import 'package:mi_finca_app/features/sync/data/services/automatic_sync.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/automatic_sync_provider.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/home/presentation/main_screens.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';
import 'package:mi_finca_app/features/sync/data/services/manual_data_refresh.dart';
import 'photo_sync_view_model_test.dart' show FakeSyncRepository;

// These tests isolate refresh presentation. Navigation tests exercise the real
// coordinator, monitor and lifecycle together.
AutomaticSync isolatedCoordinator(Ref ref) {
  final worker = AutomaticSync(
    sync: () async {},
    pendingCount: () async => 0,
    changes: const Stream<void>.empty(),
  );
  ref.onDispose(worker.dispose);
  return worker;
}

void main() {
  for (final pending in [0, 2]) {
    testWidgets('online pending=$pending allows refresh', (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeSyncRepository()..pending = pending;
      final container = ProviderContainer(
        overrides: [
          automaticSyncProvider.overrideWith(isolatedCoordinator),
          syncRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      await container.read(syncViewModelProvider.future);
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SyncScreen()),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Todo sincronizado'), findsNothing);
      expect(find.text('Nunca'), findsOneWidget);
    });
  }
  for (final manual in [false, true]) {
    testWidgets('offline manual=$manual disables refresh', (tester) async {
      final container = ProviderContainer(
        overrides: [
          automaticSyncProvider.overrideWith(isolatedCoordinator),
          syncRepositoryProvider.overrideWithValue(FakeSyncRepository()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(syncViewModelProvider.future);
      final vm = container.read(syncViewModelProvider.notifier);
      if (manual) {
        vm.setOnline(false);
      } else {
        vm.setConnectivity(false);
      }
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SyncScreen()),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Modo sin conexión'), findsOneWidget);
    });
  }
  testWidgets(
    'double tap locks full refresh and renders completion without login',
    (tester) async {
      final gate = Completer<void>();
      var calls = 0;
      final worker = ManualDataRefresh(
        validate: () async {},
        push: () async {
          calls++;
        },
        tombstones: () async {},
        downloads: {
          'animals': () async {
            await gate.future;
          },
        },
        reload: () async {},
        saveSuccess: () async {},
      );
      final container = ProviderContainer(
        overrides: [
          automaticSyncProvider.overrideWith(isolatedCoordinator),
          syncRepositoryProvider.overrideWithValue(
            FakeSyncRepository()..pending = 0,
          ),
          manualDataRefreshFactoryProvider.overrideWithValue(
            () async => worker,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(syncViewModelProvider.future);
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SyncScreen()),
        ),
      );
      await tester.ensureVisible(
        find.byWidgetPredicate((w) => w is FilledButton),
      );
      await tester.tap(find.byWidgetPredicate((w) => w is FilledButton));
      await tester.tap(find.byWidgetPredicate((w) => w is FilledButton));
      await tester.pump();
      expect(calls, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Actualizando datos...'), findsWidgets);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Datos actualizados'), findsOneWidget);
    },
  );
  testWidgets('partial result is visible and retains previous timestamp', (
    tester,
  ) async {
    final worker = ManualDataRefresh(
      validate: () async {},
      push: () async {},
      tombstones: () async {
        throw StateError('unavailable');
      },
      downloads: {},
      reload: () async {},
      saveSuccess: () async {
        fail('must not save');
      },
    );
    final container = ProviderContainer(
      overrides: [
        automaticSyncProvider.overrideWith(isolatedCoordinator),
        syncRepositoryProvider.overrideWithValue(
          FakeSyncRepository()..pending = 0,
        ),
        manualDataRefreshFactoryProvider.overrideWithValue(() async => worker),
      ],
    );
    addTearDown(container.dispose);
    await container.read(syncViewModelProvider.future);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SyncScreen()),
      ),
    );
    await container.read(syncViewModelProvider.notifier).refreshData();
    await tester.pump();
    expect(find.text('Actualización incompleta'), findsOneWidget);
    expect(find.text('Nunca'), findsOneWidget);
  });
}
