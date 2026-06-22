import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/animals/domain/repositories/animal_repository.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';
import 'package:mi_finca_app/features/expenses/domain/repositories/expense_repository.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/farm/domain/repositories/farm_repository.dart';
import 'package:mi_finca_app/features/farm/domain/entities/farm.dart';
import 'package:mi_finca_app/features/paddocks/domain/repositories/paddock_repository.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';

class LoadDemoData {
  const LoadDemoData(
    this._database,
    this._auth,
    this._farm,
    this._animals,
    this._paddocks,
    this._expenses,
  );
  final AppDatabase _database;
  final AuthRepository _auth;
  final FarmRepository _farm;
  final AnimalRepository _animals;
  final PaddockRepository _paddocks;
  final ExpenseRepository _expenses;

  Future<void> call() async {
    await _database.clearAll();
    final now = DateTime.now();
    const session = UserSession(
      id: 'demo-user',
      name: 'María',
      email: 'demo@mifinca.pe',
    );
    const farm = Farm(
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
    await _auth.saveSession(session);
    await _farm.saveFarm(farm);
    for (final item in paddocks) {
      await _paddocks.save(item);
    }
    for (final item in animals) {
      await _animals.save(item);
    }
    await _expenses.save(
      Expense(
        id: 'e1',
        category: 'Alimento',
        amount: 800,
        date: now,
        note: 'Sales minerales',
        updatedAt: now,
      ),
    );
  }
}
