import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/expenses/data/models/expense_model.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';

class ExpenseLocalDataSource {
  const ExpenseLocalDataSource(this._database);
  final AppDatabase _database;
  Future<List<Expense>> getAll() async => (await _database.readRecords(
    'expenses',
  )).map(ExpenseModel.fromJson).toList();
  Future<void> save(Expense expense) => _database.putRecord(
    'expenses',
    expense.id,
    ExpenseModel.toJson(expense),
    expense.updatedAt,
  );
}
