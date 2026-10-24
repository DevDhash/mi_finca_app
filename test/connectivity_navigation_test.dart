import 'dart:async';
import 'package:mi_finca_app/features/sync/data/services/manual_data_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/network/network_status.dart';
import 'package:mi_finca_app/core/widgets/common_widgets.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_photo_provider.dart';
import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';
import 'package:mi_finca_app/features/farm/presentation/viewmodels/farm_view_model.dart';
import 'package:mi_finca_app/features/home/presentation/main_screens.dart';
import 'package:mi_finca_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/automatic_sync_provider.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';
import 'automatic_sync_provider_test.dart' show SyncMonitor, SyncAuth;
import 'photo_sync_view_model_test.dart' show FakeSyncRepository;

class NavigationAuth extends AuthViewModel {
  @override
  Future<UserSession?> build() async =>
      const UserSession(id: 'owner', name: 'Ana', email: 'ana@example.com');
}

class NavigationFarm extends FarmViewModel {
  @override
  Future<Farm?> build() async =>
      const Farm(id: 'farm', name: 'Mi finca', location: 'Lima');
}

// Mirrors the bootstrap subscription and the Dashboard's banner on the lower
// route. No test-only listener keeps the automatic coordinator alive.
class NavigationHome extends ConsumerWidget {
  const NavigationHome({super.key, required this.page});
  final Widget page;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(automaticSyncProvider);
    final sync = ref.watch(syncViewModelProvider);
    return Scaffold(
      body: Column(
        children: [
          if (sync.hasValue) ConnectivityBanner(state: sync.requireValue),
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
  }
}

void main() {
  for (final initialOnline in [true, false]) {
    for (final profile in [false, true]) {
      testWidgets(
        '${profile ? 'Perfil' : 'Sincronización'} reacts on pushed route initialOnline=$initialOnline',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 2400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final monitor = SyncMonitor()..online = initialOnline;
          final auth = SyncAuth();
          final refreshGate = Completer<void>();
          final container = ProviderContainer(
            overrides: [
              manualDataRefreshFactoryProvider.overrideWithValue(
                () async => ManualDataRefresh(
                  validate: () async {},
                  push: () async {},
                  tombstones: () async {},
                  downloads: {'animals': () => refreshGate.future},
                  reload: () async {},
                  saveSuccess: () async {},
                ),
              ),
              networkMonitorProvider.overrideWithValue(monitor),
              animalPhotoUrlSourceProvider.overrideWithValue(auth),
              syncRepositoryProvider.overrideWithValue(
                FakeSyncRepository()..pending = 0,
              ),
              authViewModelProvider.overrideWith(NavigationAuth.new),
              farmViewModelProvider.overrideWith(NavigationFarm.new),
            ],
          );
          var disposed = false;
          addTearDown(() async {
            if (!disposed) container.dispose();
            await monitor.events.close();
            await auth.events.close();
          });
          await container.read(syncViewModelProvider.future);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: NavigationHome(
                  page: profile ? const ProfileScreen() : const SyncScreen(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            container.read(syncViewModelProvider).requireValue.isOnline,
            initialOnline,
          );
          final originalWorker = container.read(automaticSyncProvider);
          await tester.tap(find.text('Abrir'));
          await tester.pumpAndSettle();
          final worker = container.read(automaticSyncProvider);
          expect(identical(worker, originalWorker), isTrue);
          expect(worker.enabled, initialOnline);
          expect(
            find.text(initialOnline ? 'Con conexión' : 'Sin conexión'),
            findsOneWidget,
          );
          if (!initialOnline) {
            if (!profile) {
              expect(
                tester
                    .widget<FilledButton>(
                      find.byWidgetPredicate((w) => w is FilledButton),
                    )
                    .onPressed,
                isNull,
              );
            }
            monitor.emit(true);
            await tester.pumpAndSettle();
          }
          expect(find.text('Con conexión'), findsOneWidget);
          monitor.emit(false);
          await tester.pumpAndSettle();
          expect(find.text('Sin conexión'), findsOneWidget);
          if (!profile) {
            expect(
              tester
                  .widget<FilledButton>(
                    find.byWidgetPredicate((w) => w is FilledButton),
                  )
                  .onPressed,
              isNull,
            );
          }
          monitor.emit(true);
          await tester.pumpAndSettle();
          expect(find.text('Con conexión'), findsOneWidget);
          if (!profile) {
            expect(
              tester
                  .widget<FilledButton>(
                    find.byWidgetPredicate((w) => w is FilledButton),
                  )
                  .onPressed,
              isNotNull,
            );
          }
          expect(
            identical(worker, container.read(automaticSyncProvider)),
            isTrue,
          );
          final vm = container.read(syncViewModelProvider.notifier);
          vm.setOnline(false);
          await tester.pumpAndSettle();
          expect(find.text('Sin conexión'), findsOneWidget);
          expect(worker.enabled, isFalse);
          vm.setOnline(true);
          await tester.pumpAndSettle();
          expect(find.text('Con conexión'), findsOneWidget);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump(Duration.zero);
          await tester.pump(Duration.zero);
          expect(worker.enabled, isFalse);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          expect(worker.enabled, isTrue);
          expect(
            identical(worker, container.read(automaticSyncProvider)),
            isTrue,
          );
          if (!profile) {
            final refresh = vm.refreshData();
            await tester.pump(Duration.zero);
            expect(
              container.read(syncViewModelProvider).requireValue.isRefreshing,
              isTrue,
            );
            monitor.emit(false);
            await tester.pump(const Duration(milliseconds: 100));
            monitor.emit(true);
            await tester.pump(const Duration(milliseconds: 100));
            expect(find.text('Con conexión'), findsOneWidget);
            expect(
              tester
                  .widget<FilledButton>(
                    find.byWidgetPredicate((w) => w is FilledButton),
                  )
                  .onPressed,
              isNull,
            );
            refreshGate.complete();
            await refresh;
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<FilledButton>(
                    find.byWidgetPredicate((w) => w is FilledButton),
                  )
                  .onPressed,
              isNotNull,
            );
          }
          expect(
            container.read(syncViewModelProvider).requireValue.pendingChanges,
            0,
          );
          expect(
            container.read(syncViewModelProvider).requireValue.lastDataRefresh,
            isNull,
          );
          if (profile) {
            expect(find.text('Ana'), findsWidgets);
            expect(find.text('ana@example.com'), findsWidgets);
            expect(find.text('Lima'), findsOneWidget);
          }
          await tester.pageBack();
          await tester.pumpAndSettle();
          monitor.emit(false);
          await tester.pumpAndSettle();
          expect(
            find.text('Sin conexión. Tus datos se guardan en el dispositivo.'),
            findsOneWidget,
          );
          monitor.emit(true);
          await tester.pumpAndSettle();
          expect(
            find.text('Sin conexión. Tus datos se guardan en el dispositivo.'),
            findsNothing,
          );
          await tester.pumpWidget(const SizedBox());
          container.dispose();
          disposed = true;
          await tester.pump(Duration.zero);
        },
      );
    }
  }
}
