import 'package:mi_finca_app/core/database/app_database.dart';

abstract interface class SyncRemoteDataSource {
  Future<void> pushRecord(PendingRecord record);
}
