import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/expenses/domain/repositories/expense_repository.dart';
import 'package:mi_finca_app/features/expenses/presentation/expense_screens.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:mi_finca_app/features/sync/domain/repositories/sync_repository.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';

Expense item(String id, double amount) => Expense(
  id: id,
  category: 'Alimento',
  amount: amount,
  date: DateTime.now(),
  updatedAt: DateTime.now(),
  note: id,
);

class Expenses implements ExpenseRepository {
  List<Expense> items = [item('one', 20), item('two', 30)];
  int deletes = 0;
  Completer<void>? gate;
  Completer<void>? saveGate;
  Object? error;
  bool failRefresh = false;
  @override
  Future<List<Expense>> getLocal() async => List.of(items);
  @override
  Future<List<Expense>> getAll() => getLocal();
  @override
  Future<void> save(Expense e) async {
    items = [...items.where((v) => v.id != e.id), e];
    await saveGate?.future;
  }

  @override
  Future<void> deleteExpense(String id) async {
    deletes++;
    await gate?.future;
    if (error != null) throw error!;
    items = items.where((e) => e.id != id).toList();
  }

  @override
  Future<List<Expense>> refresh() async {
    items = items.where((e) => e.id != 'one').toList();
    if (failRefresh) {
      throw StateError('active GET failed after tombstone merge');
    }
    return getLocal();
  }
}

class Sync implements SyncRepository {
  int calls = 0;
  Completer<void>? gate;
  bool fail = false;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<int> pendingCount() async => 1;
  @override
  Future<DateTime?> lastSync() async => null;
  @override
  Future<void> pushPendingChanges() async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('offline');
  }
}

void main() {
  late Expenses repository;
  late Sync sync;
  late ProviderContainer container;
  setUp(() {
    repository = Expenses();
    sync = Sync();
    container = ProviderContainer(
      overrides: [
        expenseRepositoryProvider.overrideWithValue(repository),
        syncRepositoryProvider.overrideWithValue(sync),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ExpenseListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dialog(WidgetTester tester, String id) async {
    await tester.ensureVisible(find.byKey(ValueKey('delete-expense-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('delete-expense-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'confirmation required; cancellation does not remove or alter totals',
    (tester) async {
      await show(tester);
      await dialog(tester, 'one');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(repository.deletes, 0);
      expect(
        find.text('¿Estás seguro de que deseas eliminar este gasto?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repository.deletes, 0);
      expect(find.byKey(const ValueKey('delete-expense-one')), findsOneWidget);
      expect(container.read(monthlyExpenseTotalProvider), 50);
    },
  );
  testWidgets(
    'local acceptance removes item and totals before remote completion',
    (tester) async {
      sync.gate = Completer<void>();
      await show(tester);
      await dialog(tester, 'one');
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('delete-expense-one')), findsNothing);
      expect(find.text('Gasto eliminado.'), findsOneWidget);
      expect(container.read(monthlyExpenseTotalProvider), 30);
      expect(
        tester.widget<Text>(find.byKey(const Key('expense-month-count'))).data,
        '1',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('expense-month-total'))).data,
        'S/ 30',
      );
      expect(sync.calls, 1);
      sync.gate!.complete();
      await tester.pumpAndSettle();
    },
  );
  testWidgets('offline mode accepts delete without remote request', (
    tester,
  ) async {
    await container.read(syncViewModelProvider.future);
    container.read(syncViewModelProvider.notifier).setOnline(false);
    await show(tester);
    await dialog(tester, 'one');
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(sync.calls, 0);
    expect(find.text('Gasto eliminado.'), findsOneWidget);
    expect(container.read(monthlyExpenseTotalProvider), 30);
  });
  testWidgets(
    'remote failure does not report accepted local delete as failed',
    (tester) async {
      sync.fail = true;
      await show(tester);
      await dialog(tester, 'one');
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(find.text('Gasto eliminado.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(container.read(monthlyExpenseTotalProvider), 30);
    },
  );
  testWidgets('double confirmation taps issue only one deletion', (
    tester,
  ) async {
    repository.gate = Completer<void>();
    await show(tester);
    await dialog(tester, 'one');
    final callback = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Eliminar'))
        .onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(repository.deletes, 1);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
          .onPressed,
      isNull,
    );
    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(container.read(monthlyExpenseTotalProvider), 30);
  });
  testWidgets('two sequential deletions update list and total independently', (
    tester,
  ) async {
    await show(tester);
    for (final id in ['one', 'two']) {
      await dialog(tester, id);
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
    }
    expect(repository.deletes, 2);
    expect(container.read(monthlyExpenseTotalProvider), 0);
    expect(
      tester.widget<Text>(find.byKey(const Key('expense-month-count'))).data,
      '0',
    );
  });
  testWidgets('local failure retains dialog and expense; retry succeeds', (
    tester,
  ) async {
    repository.error = StateError('disk');
    await show(tester);
    await dialog(tester, 'one');
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudo eliminar el gasto. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(container.read(monthlyExpenseTotalProvider), 50);
    repository.error = null;
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(container.read(monthlyExpenseTotalProvider), 30);
  });
  testWidgets('legacy verification error is understandable and keeps expense', (
    tester,
  ) async {
    repository.error = const ExpenseOwnershipUnverified();
    await show(tester);
    await dialog(tester, 'one');
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Conéctate con la cuenta'), findsOneWidget);
    expect(container.read(monthlyExpenseTotalProvider), 50);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });
  testWidgets(
    'refresh applies remote deletion even if subsequent active download fails',
    (tester) async {
      repository.failRefresh = true;
      await show(tester);
      await tester.tap(find.byTooltip('Actualizar gastos'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('delete-expense-one')), findsNothing);
      expect(container.read(monthlyExpenseTotalProvider), 30);
      expect(find.textContaining('No se pudo actualizar.'), findsOneWidget);
    },
  );
  test(
    'viewmodel coalesces concurrent requests for the same expense',
    () async {
      await container.read(expenseViewModelProvider.future);
      repository.gate = Completer<void>();
      final model = container.read(expenseViewModelProvider.notifier);
      final first = model.deleteExpense('one');
      final second = model.deleteExpense('one');
      expect(repository.deletes, 1);
      repository.gate!.complete();
      await Future.wait([first, second]);
      expect(container.read(monthlyExpenseTotalProvider), 30);
      await container.read(syncViewModelProvider.future);
    },
  );
  test(
    'late save completion cannot restore an expense deleted meanwhile',
    () async {
      await container.read(expenseViewModelProvider.future);
      repository.saveGate = Completer<void>();
      final model = container.read(expenseViewModelProvider.notifier);
      final save = model.save(item('one', 99));
      await model.deleteExpense('one');
      repository.saveGate!.complete();
      await save;
      expect(container.read(monthlyExpenseTotalProvider), 30);
      expect(
        container.read(expenseViewModelProvider).requireValue.map((e) => e.id),
        ['two'],
      );
      await container.read(syncViewModelProvider.future);
    },
  );
}
