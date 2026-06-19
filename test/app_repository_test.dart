import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/models/app_models.dart';
import 'package:mi_finca_app/core/repositories/app_repository.dart';

void main() {
  late AppDatabase database;
  late LocalAppRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = LocalAppRepository(database);
  });

  tearDown(() => database.close());

  test('persists a session and animal locally', () async {
    const session = UserSession(id: 'u1', name: 'Ana', email: 'ana@test.pe');
    final now = DateTime(2026, 6, 19);
    final animal = Animal(
      id: 'a1',
      code: 'V-001',
      type: 'Vaca',
      breed: 'Holstein',
      sex: 'Hembra',
      createdAt: now,
      updatedAt: now,
    );

    await repository.saveSession(session);
    await repository.saveAnimal(animal);

    expect((await repository.session())?.email, session.email);
    expect((await repository.animals()).single.code, animal.code);
    expect(await repository.pendingCount(), 1);
  });

  test('marks the local outbox as synchronized', () async {
    final now = DateTime(2026, 6, 19);
    await repository.saveExpense(
      Expense(
        id: 'e1',
        category: 'Alimento',
        amount: 120,
        date: now,
        updatedAt: now,
      ),
    );

    await repository.markAllSynced();

    expect(await repository.pendingCount(), 0);
    expect(await repository.lastSync(), isNotNull);
  });
}
