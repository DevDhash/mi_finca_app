import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/expenses/presentation/expense_screens.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';

class ListExpenseViewModel extends ExpenseViewModel {
  ListExpenseViewModel(this.items);
  final List<Expense> items;
  @override
  Future<List<Expense>> build() async => items;
}

Expense expense(String id, DateTime date, double amount) => Expense(
  id: id,
  category: 'Alimento',
  amount: amount,
  date: date,
  note: id,
  updatedAt: date,
);
String label(DateTime date) {
  final value = DateFormat('MMMM yyyy', 'es').format(date);
  return value[0].toUpperCase() + value.substring(1);
}

Future<void> showList(WidgetTester tester, List<Expense> items) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        expenseViewModelProvider.overrideWith(
          () => ListExpenseViewModel(items),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const ExpenseListScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> selectMonth(WidgetTester tester, DateTime month) async {
  await tester.tap(find.byType(DropdownButtonFormField<DateTime>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label(month)).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'title, current month and fixed registration button open unchanged form',
    (tester) async {
      await showList(tester, []);
      expect(find.text('Gastos de la finca'), findsOneWidget);
      expect(tester.widget<AppBar>(find.byType(AppBar)).centerTitle, isTrue);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.add),
        ),
        findsNothing,
      );
      expect(find.text(label(DateTime.now())), findsOneWidget);
      expect(find.text('Registrar gasto'), findsOneWidget);
      expect(find.text('S/ 0,00'), findsOneWidget);
      await tester.tap(find.text('Registrar gasto'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseFormScreen), findsOneWidget);
    },
  );

  testWidgets('month selection filters, orders and updates total and count', (
    tester,
  ) async {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    final previous = DateTime(now.year, now.month - 1);
    await showList(tester, [
      expense('actual-antiguo', current, 50),
      expense('historico', previous, 1250),
      expense('actual-reciente', current.add(const Duration(days: 1)), 500.5),
    ]);
    expect(find.textContaining('actual-antiguo'), findsOneWidget);
    expect(find.textContaining('actual-reciente'), findsOneWidget);
    expect(find.textContaining('historico'), findsNothing);
    expect(find.text('S/ 550,50'), findsOneWidget);
    expect(find.text('2 gastos'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('expense-month-count'))).data,
      '2',
    );
    expect(
      tester.getTopLeft(find.textContaining('actual-reciente')).dy,
      lessThan(tester.getTopLeft(find.textContaining('actual-antiguo')).dy),
    );
    final dropdown = tester.widget<DropdownButtonFormField<DateTime>>(
      find.byType(DropdownButtonFormField<DateTime>),
    );
    // Menu entries deduplicate months and order newest first.
    expect(dropdown.initialValue, current);
    await selectMonth(tester, previous);
    expect(find.textContaining('historico'), findsOneWidget);
    expect(find.textContaining('actual-reciente'), findsNothing);
    expect(find.text('S/ 1.250,00'), findsNWidgets(2));
    expect(find.text('1 gasto'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('expense-month-count'))).data,
      '1',
    );
  });

  testWidgets('empty current month retains historical month and expenses', (
    tester,
  ) async {
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1);
    await showList(tester, [expense('anterior', previous, 50)]);
    expect(find.text('Sin gastos en ${label(now)}'), findsOneWidget);
    expect(
      find.text('Cuando registres un gasto aparecerá aquí.'),
      findsOneWidget,
    );
    expect(find.text('0 gastos'), findsOneWidget);
    await selectMonth(tester, previous);
    expect(find.textContaining('anterior'), findsOneWidget);
    expect(find.text('S/ 50,00'), findsNWidgets(2));
    await selectMonth(tester, DateTime(now.year, now.month));
    expect(find.text('Sin gastos en ${label(now)}'), findsOneWidget);
  });

  testWidgets('small screen keeps button visible with a long list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    await showList(
      tester,
      List.generate(
        25,
        (i) =>
            expense('Gasto $i con una nota larga de alimentación', now, 500.5),
      ),
    );
    expect(find.text('Registrar gasto').hitTestable(), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(find.text('Registrar gasto').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
