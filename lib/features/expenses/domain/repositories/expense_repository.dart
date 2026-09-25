import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';

abstract interface class ExpenseRepository {
  Future<List<Expense>> getAll();
  Future<void> save(Expense expense);
  Future<void> deleteExpense(String expenseId);
  Future<List<Expense>> refresh();
  Future<List<Expense>> getLocal();
}

class ExpenseOwnershipUnverified implements Exception {
  const ExpenseOwnershipUnverified();
}
