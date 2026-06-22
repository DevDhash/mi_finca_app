import 'package:mi_finca_app/core/domain/sync_status.dart';

class Expense {
  const Expense({
    required this.id,
    required this.category,
    required this.amount,
    required this.date,
    this.note = '',
    required this.updatedAt,
    this.syncStatus = SyncStatus.pending,
  });
  final String id;
  final String category;
  final double amount;
  final DateTime date;
  final String note;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
}
