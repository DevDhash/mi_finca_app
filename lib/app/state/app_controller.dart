import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/models/app_models.dart';
import 'package:mi_finca_app/core/repositories/app_repository.dart';
import 'package:uuid/uuid.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final repositoryProvider = Provider<AppRepository>(
  (ref) => LocalAppRepository(ref.watch(databaseProvider)),
);

final remoteGatewayProvider = Provider<RemoteGateway>(
  (ref) => MockRemoteGateway(),
);

final appControllerProvider = AsyncNotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppState {
  const AppState({
    this.session,
    this.farm,
    this.animals = const [],
    this.paddocks = const [],
    this.expenses = const [],
    this.movements = const [],
    this.pendingChanges = 0,
    this.lastSync,
    this.isOnline = true,
    this.isSyncing = false,
  });
  final UserSession? session;
  final Farm? farm;
  final List<Animal> animals;
  final List<Paddock> paddocks;
  final List<Expense> expenses;
  final List<Movement> movements;
  final int pendingChanges;
  final DateTime? lastSync;
  final bool isOnline;
  final bool isSyncing;

  AppState copyWith({
    UserSession? session,
    Farm? farm,
    List<Animal>? animals,
    List<Paddock>? paddocks,
    List<Expense>? expenses,
    List<Movement>? movements,
    int? pendingChanges,
    DateTime? lastSync,
    bool? isOnline,
    bool? isSyncing,
    bool clearSession = false,
    bool clearFarm = false,
  }) => AppState(
    session: clearSession ? null : session ?? this.session,
    farm: clearFarm ? null : farm ?? this.farm,
    animals: animals ?? this.animals,
    paddocks: paddocks ?? this.paddocks,
    expenses: expenses ?? this.expenses,
    movements: movements ?? this.movements,
    pendingChanges: pendingChanges ?? this.pendingChanges,
    lastSync: lastSync ?? this.lastSync,
    isOnline: isOnline ?? this.isOnline,
    isSyncing: isSyncing ?? this.isSyncing,
  );

  double get monthlyExpenses {
    final now = DateTime.now();
    return expenses
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .fold(0, (sum, e) => sum + e.amount);
  }
}

class AppController extends AsyncNotifier<AppState> {
  AppRepository get _repository => ref.read(repositoryProvider);
  static const _uuid = Uuid();

  @override
  Future<AppState> build() async => AppState(
    session: await _repository.session(),
    farm: await _repository.farm(),
    animals: await _repository.animals(),
    paddocks: await _repository.paddocks(),
    expenses: await _repository.expenses(),
    movements: await _repository.movements(),
    pendingChanges: await _repository.pendingCount(),
    lastSync: await _repository.lastSync(),
  );

  Future<void> login({
    required String email,
    required String password,
    String? name,
  }) async {
    if (email.trim().isEmpty || password.length < 4) {
      throw const FormatException(
        'Ingresa un correo y una clave de al menos 4 caracteres.',
      );
    }
    final session = UserSession(
      id: _uuid.v4(),
      name: name?.trim().isNotEmpty == true
          ? name!.trim()
          : email.split('@').first,
      email: email.trim(),
    );
    await _repository.saveSession(session);
    state = AsyncData(state.requireValue.copyWith(session: session));
  }

  Future<void> enterDemo() async {
    await _repository.clearAll();
    final now = DateTime.now();
    final session = const UserSession(
      id: 'demo-user',
      name: 'María',
      email: 'demo@mifinca.pe',
    );
    final farm = const Farm(
      id: 'demo-farm',
      name: 'Finca El Porvenir',
      location: 'Cajamarca',
    );
    final paddocks = [
      Paddock(
        id: 'p1',
        name: 'Potrero Norte',
        areaHectares: 4.5,
        grassType: 'Rye grass',
        status: 'En uso',
        lastUsedAt: now.subtract(const Duration(days: 2)),
        createdAt: now,
        updatedAt: now,
      ),
      Paddock(
        id: 'p2',
        name: 'Potrero La Loma',
        areaHectares: 3.2,
        grassType: 'Kikuyo',
        status: 'Disponible',
        lastUsedAt: now.subtract(const Duration(days: 34)),
        createdAt: now,
        updatedAt: now,
      ),
      Paddock(
        id: 'p3',
        name: 'Potrero Bajo',
        areaHectares: 2.8,
        grassType: 'Trébol',
        status: 'Descansando',
        lastUsedAt: now.subtract(const Duration(days: 18)),
        createdAt: now,
        updatedAt: now,
      ),
    ];
    final animals = [
      Animal(
        id: 'a1',
        code: 'V-014',
        name: 'Lola',
        type: 'Vaca',
        breed: 'Holstein',
        sex: 'Hembra',
        weight: 485,
        paddockId: 'p1',
        createdAt: now,
        updatedAt: now,
      ),
      Animal(
        id: 'a2',
        code: 'T-215',
        name: 'Lucero',
        type: 'Ternero',
        breed: 'Brown Swiss',
        sex: 'Macho',
        weight: 135,
        paddockId: 'p1',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now,
      ),
    ];
    final expenses = [
      Expense(
        id: 'e1',
        category: 'Alimento',
        amount: 800,
        date: now,
        note: 'Sales minerales',
        updatedAt: now,
      ),
    ];
    await _repository.saveSession(session);
    await _repository.saveFarm(farm);
    for (final p in paddocks) {
      await _repository.savePaddock(p);
    }
    for (final a in animals) {
      await _repository.saveAnimal(a);
    }
    for (final e in expenses) {
      await _repository.saveExpense(e);
    }
    state = AsyncData(
      AppState(
        session: session,
        farm: farm,
        animals: animals,
        paddocks: paddocks,
        expenses: expenses,
        pendingChanges: await _repository.pendingCount(),
      ),
    );
  }

  Future<void> configureFarm(
    String name,
    String location,
    String firstPaddock,
  ) async {
    final now = DateTime.now();
    final farm = Farm(
      id: _uuid.v4(),
      name: name.trim(),
      location: location.trim(),
    );
    await _repository.saveFarm(farm);
    var current = state.requireValue.copyWith(farm: farm);
    if (firstPaddock.trim().isNotEmpty) {
      final paddock = Paddock(
        id: _uuid.v4(),
        name: firstPaddock.trim(),
        areaHectares: 1,
        grassType: 'Por definir',
        createdAt: now,
        updatedAt: now,
      );
      await _repository.savePaddock(paddock);
      current = current.copyWith(paddocks: [paddock]);
    }
    state = AsyncData(
      current.copyWith(pendingChanges: await _repository.pendingCount()),
    );
  }

  Future<void> saveAnimal(Animal animal) async {
    await _repository.saveAnimal(animal);
    final items = [...state.requireValue.animals];
    final index = items.indexWhere((item) => item.id == animal.id);
    if (index < 0) {
      items.insert(0, animal);
    } else {
      items[index] = animal;
    }
    state = AsyncData(
      state.requireValue.copyWith(
        animals: items,
        pendingChanges: await _repository.pendingCount(),
      ),
    );
  }

  Future<void> savePaddock(Paddock paddock) async {
    await _repository.savePaddock(paddock);
    final items = [...state.requireValue.paddocks];
    final index = items.indexWhere((item) => item.id == paddock.id);
    if (index < 0) {
      items.insert(0, paddock);
    } else {
      items[index] = paddock;
    }
    state = AsyncData(
      state.requireValue.copyWith(
        paddocks: items,
        pendingChanges: await _repository.pendingCount(),
      ),
    );
  }

  Future<void> saveExpense(Expense expense) async {
    await _repository.saveExpense(expense);
    state = AsyncData(
      state.requireValue.copyWith(
        expenses: [expense, ...state.requireValue.expenses],
        pendingChanges: await _repository.pendingCount(),
      ),
    );
  }

  Future<void> moveAnimal(
    Animal animal,
    String destinationId,
    DateTime date,
  ) async {
    final movement = Movement(
      id: _uuid.v4(),
      animalId: animal.id,
      fromPaddockId: animal.paddockId,
      toPaddockId: destinationId,
      date: date,
    );
    final moved = animal.copyWith(
      paddockId: destinationId,
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
    );
    await _repository.saveMovement(movement);
    await _repository.saveAnimal(moved);
    final animals = state.requireValue.animals
        .map((a) => a.id == moved.id ? moved : a)
        .toList();
    state = AsyncData(
      state.requireValue.copyWith(
        animals: animals,
        movements: [movement, ...state.requireValue.movements],
        pendingChanges: await _repository.pendingCount(),
      ),
    );
  }

  void setOnline(bool value) =>
      state = AsyncData(state.requireValue.copyWith(isOnline: value));

  Future<void> syncNow() async {
    final current = state.requireValue;
    if (!current.isOnline || current.pendingChanges == 0) return;
    state = AsyncData(current.copyWith(isSyncing: true));
    await ref.read(remoteGatewayProvider).pushChanges();
    await _repository.markAllSynced();
    state = AsyncData(
      state.requireValue.copyWith(
        isSyncing: false,
        pendingChanges: 0,
        lastSync: DateTime.now(),
      ),
    );
  }

  Future<void> signOut() async {
    await _repository.signOut();
    state = AsyncData(state.requireValue.copyWith(clearSession: true));
  }
}
