import 'package:mi_finca_app/core/domain/sync_status.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnimalRemoteDataSource {
  const AnimalRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<void> upsertAnimal(Animal animal) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw const AuthException('No hay usuario autenticado.');
    }

    await _client.from('animals').upsert({
      'id': animal.id,
      'user_id': user.id,
      'code': animal.code,
      'name': animal.name,
      'type': animal.type,
      'breed': animal.breed,
      'sex': animal.sex,
      'photo_path': animal.photoPath,
      'birth_date': animal.birthDate?.toIso8601String(),
      'weight': animal.weight,
      'paddock_id': animal.paddockId,
      'notes': animal.notes,
      'status': animal.status,
      'created_at': animal.createdAt.toIso8601String(),
      'updated_at': animal.updatedAt.toIso8601String(),
    });
  }

  Future<void> upsertMovement(Movement movement) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw const AuthException('No hay usuario autenticado.');
    }

    await _client.from('animal_movements').upsert({
      'id': movement.id,
      'user_id': user.id,
      'animal_id': movement.animalId,
      'from_paddock_id': movement.fromPaddockId,
      'to_paddock_id': movement.toPaddockId,
      'moved_at': movement.date.toIso8601String(),
      'created_at': movement.date.toIso8601String(),
      'updated_at': movement.date.toIso8601String(),
    });
  }

  Future<List<Animal>> getAnimals() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw const AuthException('No hay usuario autenticado.');
    }

    final response = await _client
        .from('animals')
        .select(
          'id, code, name, type, breed, sex, photo_path, birth_date, weight, paddock_id, notes, status, created_at, updated_at',
        )
        .eq('user_id', user.id)
        .isFilter('deleted_at', null)
        .order('updated_at', ascending: false);

    return response
        .map(
          (json) => Animal(
            id: json['id'] as String,
            code: json['code'] as String,
            name: json['name'] as String?,
            type: json['type'] as String,
            breed: json['breed'] as String? ?? '',
            sex: json['sex'] as String? ?? '',
            photoPath: json['photo_path'] as String?,
            birthDate: json['birth_date'] == null
                ? null
                : DateTime.parse(json['birth_date'] as String),
            weight: (json['weight'] as num?)?.toDouble(),
            paddockId: json['paddock_id'] as String?,
            notes: json['notes'] as String? ?? '',
            status: json['status'] as String? ?? 'Activo',
            createdAt: DateTime.parse(json['created_at'] as String),
            updatedAt: DateTime.parse(json['updated_at'] as String),
            syncStatus: SyncStatus.synced,
          ),
        )
        .toList();
  }

  Future<List<Movement>> getMovements() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw const AuthException('No hay usuario autenticado.');
    }

    final response = await _client
        .from('animal_movements')
        .select('id, animal_id, from_paddock_id, to_paddock_id, moved_at')
        .eq('user_id', user.id)
        .isFilter('deleted_at', null)
        .order('moved_at', ascending: false);

    return response
        .where((json) => json['to_paddock_id'] != null)
        .map(
          (json) => Movement(
            id: json['id'] as String,
            animalId: json['animal_id'] as String,
            fromPaddockId: json['from_paddock_id'] as String?,
            toPaddockId: json['to_paddock_id'] as String,
            date: DateTime.parse(json['moved_at'] as String),
          ),
        )
        .toList();
  }
}
