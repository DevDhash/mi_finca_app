import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/expenses/presentation/expense_screens.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';

class ControlledExpenseViewModel extends ExpenseViewModel {
  final saves = <Expense>[];
  Completer<void> completion = Completer<void>();
  @override
  Future<List<Expense>> build() async => [];
  @override
  Future<void> save(Expense expense) {
    saves.add(expense);
    return completion.future;
  }
}

Future<void> openForm(
  WidgetTester tester,
  ControlledExpenseViewModel model,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [expenseViewModelProvider.overrideWith(() => model)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openExpenseForm(context),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, '12,50');
  await tester.enterText(find.byType(TextField).last, 'Mi nota');
  await tester.ensureVisible(find.byType(FilledButton));
}

void main() {
  testWidgets('two taps before rebuild save once and pop after success', (
    tester,
  ) async {
    final model = ControlledExpenseViewModel();
    await openForm(tester, model);
    await tester.tap(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(model.saves, hasLength(1));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final saved = model.saves.single;
    expect(saved.amount, 12.5);
    expect(
      saved.date,
      DateTime(saved.date.year, saved.date.month, saved.date.day),
    );
    model.completion.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseFormScreen), findsNothing);
  });

  testWidgets('failure preserves inputs and enables retry', (tester) async {
    final model = ControlledExpenseViewModel();
    await openForm(tester, model);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    model.completion.completeError(StateError('Local write failed'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseFormScreen), findsOneWidget);
    expect(
      find.text('No se pudo guardar el gasto. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '12,50',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'Mi nota',
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    model.completion = Completer<void>();
    await tester.tap(find.byType(FilledButton));
    expect(model.saves, hasLength(2));
    model.completion.complete();
    await tester.pumpAndSettle();
  });
}
