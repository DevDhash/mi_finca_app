import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_remote_datasource.dart';
import 'package:mi_finca_app/features/animals/data/repositories/animal_repository_impl.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:mi_finca_app/features/auth/data/datasources/supabase_auth_datasource.dart';
import 'package:mi_finca_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_local_datasource.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:mi_finca_app/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/farm/data/datasources/farm_local_datasource.dart';
import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';
import 'package:mi_finca_app/features/farm/domain/repositories/farm_repository.dart';
import 'package:mi_finca_app/features/onboarding/domain/usecases/configure_farm.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/repositories/paddock_repository.dart';
import 'package:mi_finca_app/features/sync/data/datasources/mock_sync_remote_datasource.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase database;
  late AuthRepositoryImpl authRepository;
  late AnimalRepositoryImpl animalRepository;
  late ExpenseRepositoryImpl expenseRepository;
  late SyncRepositoryImpl syncRepository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());

    final testSupabaseClient = SupabaseClient(
      'https://test.supabase.co',
      'test-publishable-key',
    );

    authRepository = AuthRepositoryImpl(
      local: AuthLocalDataSource(database),
      remote: _FakeAuthRemoteDataSource(testSupabaseClient),
    );

    animalRepository = AnimalRepositoryImpl(
      local: AnimalLocalDataSource(database),
      remote: _FakeAnimalRemoteDataSource(testSupabaseClient),
    );

    expenseRepository = ExpenseRepositoryImpl(
      local: ExpenseLocalDataSource(database),
      remote: ExpenseRemoteDataSource(testSupabaseClient),
    );

    syncRepository = SyncRepositoryImpl(
      SyncLocalDataSource(database),
      const MockSyncRemoteDataSource(),
    );
  });

  tearDown(() => database.close());

  test('persists a session and animal as a pending local change', () async {
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

  test('sign out clears local user data and pending records', () async {
    const session = UserSession(id: 'u1', name: 'Ana', email: 'ana@test.pe');
    final now = DateTime(2026, 6, 19);
    final farmLocalDataSource = FarmLocalDataSource(database);

    await authRepository.saveSession(session);
    await farmLocalDataSource.write(
      const Farm(id: 'f1', name: 'Finca Norte', location: 'Junin'),
    );
    await animalRepository.save(
      Animal(
        id: 'a1',
        code: 'V-001',
        type: 'Vaca',
        breed: 'Holstein',
        sex: 'Hembra',
        createdAt: now,
        updatedAt: now,
      ),
    );

    expect(await syncRepository.pendingCount(), 1);

    await authRepository.signOut();

    expect(await authRepository.currentSession(), isNull);
    expect(await farmLocalDataSource.read(), isNull);
    expect(await animalRepository.getAll(), isEmpty);
    expect(await syncRepository.pendingCount(), 0);
  });

  test('configures the first paddock with the selected rest days', () async {
    final farmRepository = _MemoryFarmRepository();
    final paddockRepository = _MemoryPaddockRepository();
    final configureFarm = ConfigureFarm(farmRepository, paddockRepository);

    final farm = await configureFarm('Finca Sur', 'Cusco', 'Potrero Alto', 45);

    expect(farm.name, 'Finca Sur');
    expect(farmRepository.savedFarm, same(farm));
    expect(paddockRepository.savedPaddocks, hasLength(1));

    final firstPaddock = paddockRepository.savedPaddocks.single;
    expect(firstPaddock.name, 'Potrero Alto');
    expect(firstPaddock.status, 'En uso');
    expect(firstPaddock.requiredRestDays, 45);
    expect(firstPaddock.lastGrazingEndDate, isNull);
  });
}

class _FakeAuthRemoteDataSource extends SupabaseAuthDatasource {
  _FakeAuthRemoteDataSource(super.client);

  @override
  Future<void> signOut() async {}
}

class _FakeAnimalRemoteDataSource extends AnimalRemoteDataSource {
  const _FakeAnimalRemoteDataSource(super.client);

  @override
  Future<void> upsertAnimal(Animal animal) async {}

  @override
  Future<void> upsertMovement(Movement movement) async {}

  @override
  Future<List<Animal>> getAnimals() async => [];

  @override
  Future<List<Movement>> getMovements() async => [];
}

class _MemoryFarmRepository implements FarmRepository {
  Farm? savedFarm;

  @override
  Future<Farm?> getFarm() async => savedFarm;

  @override
  Future<void> saveFarm(Farm farm) async {
    savedFarm = farm;
  }
}

class _MemoryPaddockRepository implements PaddockRepository {
  final savedPaddocks = <Paddock>[];

  @override
  Future<List<Paddock>> getAll() async => savedPaddocks;

  @override
  Future<void> save(Paddock paddock) async {
    savedPaddocks.add(paddock);
  }
}
