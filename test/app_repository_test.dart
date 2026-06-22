import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/data/repositories/animal_repository_impl.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:mi_finca_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_local_datasource.dart';
import 'package:mi_finca_app/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/sync/data/datasources/mock_sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';

void main() {
  late AppDatabase database;
  late AuthRepositoryImpl authRepository;
  late AnimalRepositoryImpl animalRepository;
  late ExpenseRepositoryImpl expenseRepository;
  late SyncRepositoryImpl syncRepository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    authRepository = AuthRepositoryImpl(AuthLocalDataSource(database));
    animalRepository = AnimalRepositoryImpl(AnimalLocalDataSource(database));
    expenseRepository = ExpenseRepositoryImpl(ExpenseLocalDataSource(database));
    syncRepository = SyncRepositoryImpl(
      SyncLocalDataSource(database),
      const MockSyncRemoteDataSource(),
    );
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

    await authRepository.saveSession(session);
    await animalRepository.save(animal);

    expect((await authRepository.currentSession())?.email, session.email);
    expect((await animalRepository.getAll()).single.code, animal.code);
    expect(await syncRepository.pendingCount(), 1);
  });

  test('marks the local outbox as synchronized', () async {
    final now = DateTime(2026, 6, 19);
    await expenseRepository.save(
      Expense(
        id: 'e1',
        category: 'Alimento',
        amount: 120,
        date: now,
        updatedAt: now,
      ),
    );

    await syncRepository.pushPendingChanges();

    expect(await syncRepository.pendingCount(), 0);
    expect(await syncRepository.lastSync(), isNotNull);
  });
}
