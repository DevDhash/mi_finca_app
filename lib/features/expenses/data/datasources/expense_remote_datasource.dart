import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExpenseRemoteDataSource {
  const ExpenseRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<void> upsert(Expense expense) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw const AuthException('No hay usuario autenticado.');
    }

    await _client.from('expenses').upsert({
      'id': expense.id,
      'user_id': user.id,
      'category': expense.category,
      'amount': expense.amount,
      'date': expense.date.toIso8601String(),
      'note': expense.note,
      'updated_at': expense.updatedAt.toIso8601String(),
    });
  }

  Future<List<Expense>> getAll() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw const AuthException('No hay usuario autenticado.');
    }

    final response = await _client
        .from('expenses')
        .select('id, category, amount, date, note, updated_at')
        .eq('user_id', user.id)
        .isFilter('deleted_at', null)
        .order('date', ascending: false);

    return response
        .map(
          (json) => Expense(
            id: json['id'] as String,
            category: json['category'] as String? ?? '',
            amount: (json['amount'] as num?)?.toDouble() ?? 0,
            date: DateTime.parse(json['date'] as String),
            note: json['note'] as String? ?? '',
            updatedAt: DateTime.parse(json['updated_at'] as String),
            syncStatus: SyncStatus.synced,
          ),
        )
        .toList();
  }
}
