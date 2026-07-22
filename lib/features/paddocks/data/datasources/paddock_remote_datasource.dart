import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaddockRemoteDataSource {
  const PaddockRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<void> upsert(Paddock paddock) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw const AuthException('No hay usuario autenticado.');
    }

    await _client.from('paddocks').upsert({
      'id': paddock.id,
      'user_id': user.id,
      'name': paddock.name,
      'area': paddock.areaHectares,
      'pasture_type': paddock.pastureType,
      'required_rest_days': paddock.requiredRestDays,
      'status': paddock.status,
      'last_grazing_end_date': paddock.lastGrazingEndDate?.toIso8601String(),
      'created_at': paddock.createdAt.toIso8601String(),
      'updated_at': paddock.updatedAt.toIso8601String(),
    });
  }

  Future<List<Paddock>> getAll() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw const AuthException('No hay usuario autenticado.');
    }

    final response = await _client
        .from('paddocks')
        .select(
          'id, name, area, pasture_type, required_rest_days, status, last_grazing_end_date, created_at, updated_at',
        )
        .eq('user_id', user.id)
        .isFilter('deleted_at', null)
        .order('updated_at', ascending: false);

    return response
        .map(
          (json) => Paddock(
            id: json['id'] as String,
            name: json['name'] as String,
            areaHectares: (json['area'] as num?)?.toDouble() ?? 0,
            pastureType: json['pasture_type'] as String?,
            requiredRestDays: (json['required_rest_days'] as num?)?.toInt(),
            status: json['status'] as String? ?? 'Disponible',
            lastGrazingEndDate: json['last_grazing_end_date'] == null
                ? null
                : DateTime.parse(json['last_grazing_end_date'] as String),
            createdAt: DateTime.parse(json['created_at'] as String),
            updatedAt: DateTime.parse(json['updated_at'] as String),
            syncStatus: SyncStatus.synced,
          ),
        )
        .toList();
  }
}
