import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';

abstract final class ExpenseModel {
  static Map<String, Object?> toJson(Expense v) => {
    'id': v.id,
    'category': v.category,
    'amount': v.amount,
    'date': v.date.toIso8601String(),
    'note': v.note,
    'updatedAt': v.updatedAt.toIso8601String(),
    'syncStatus': v.syncStatus.name,
  };
  static Expense fromJson(Map<String, Object?> j) => Expense(
    id: j['id']! as String,
    category: j['category']! as String,
    amount: (j['amount']! as num).toDouble(),
    date: DateTime.parse(j['date']! as String),
    note: j['note'] as String? ?? '',
    updatedAt: DateTime.parse(j['updatedAt']! as String),
    syncStatus: SyncStatus.values.byName(
      j['syncStatus'] as String? ?? 'pending',
    ),
  );
}
