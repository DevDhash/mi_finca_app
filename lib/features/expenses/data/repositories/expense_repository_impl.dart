import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_local_datasource.dart';
import 'package:mi_finca_app/features/expenses/domain/repositories/expense_repository.dart';

class ExpenseRepositoryImpl implements ExpenseRepository {
  const ExpenseRepositoryImpl(this._local);
  final ExpenseLocalDataSource _local;
  @override
  Future<List<Expense>> getAll() => _local.getAll();
  @override
  Future<void> save(Expense expense) => _local.save(expense);
}
