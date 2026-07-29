import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/paddocks/data/models/paddock_model.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/usecases/calculate_paddock_rotation.dart';

void main() {
  final referenceDate = DateTime(2026, 7, 20);
  const calculate = CalculatePaddockRotation();

  group('CalculatePaddockRotation', () {
    test('returns the active paddock with the real animal count', () {
      final active = _paddock(
        id: 'p1',
        name: 'Norte',
        status: 'En uso',
        grazingStartDate: referenceDate.subtract(const Duration(days: 3)),
        plannedGrazingDays: 7,
      );
      final summary = calculate(
        paddocks: [
          active,
          _paddock(
            id: 'p2',
            name: 'Loma',
            status: 'Descansando',
            requiredRestDays: 20,
            lastGrazingEndDate: referenceDate.subtract(const Duration(days: 8)),
          ),
        ],
        animals: [
          _animal(id: 'a1', paddockId: 'p1'),
          _animal(id: 'a2', paddockId: 'p1'),
          _animal(id: 'a3', paddockId: 'p2'),
          _animal(id: 'a4'),
        ],
        referenceDate: referenceDate,
      );

      expect(summary.active?.paddock.name, 'Norte');
      expect(summary.active?.animalCount, 2);
      expect(summary.active?.elapsedGrazingDays, 3);
      expect(summary.active?.remainingGrazingDays, 4);
      expect(summary.active?.hasGrazingPlan, isTrue);
      expect(summary.active?.isOverdue, isFalse);
      expect(summary.active?.isDueSoon, isFalse);
      expect(summary.active?.isDueToday, isFalse);
    });

    test('marks active grazing as overdue when planned days are exceeded', () {
      final summary = calculate(
        paddocks: [
          _paddock(
            id: 'p1',
            name: 'Norte',
            status: 'En uso',
            grazingStartDate: referenceDate.subtract(const Duration(days: 9)),
            plannedGrazingDays: 7,
          ),
        ],
        animals: const [],
        referenceDate: referenceDate,
      );

      expect(summary.active?.elapsedGrazingDays, 9);
      expect(summary.active?.remainingGrazingDays, -2);
      expect(summary.active?.isOverdue, isTrue);
    });

    test('marks active grazing as due soon and due today', () {
      final dueSoon = calculate(
        paddocks: [
          _paddock(
            id: 'p1',
            name: 'Norte',
            status: 'En uso',
            grazingStartDate: referenceDate.subtract(const Duration(days: 5)),
            plannedGrazingDays: 7,
          ),
        ],
        animals: const [],
        referenceDate: referenceDate,
      );
      final dueToday = calculate(
        paddocks: [
          _paddock(
            id: 'p1',
            name: 'Norte',
            status: 'En uso',
            grazingStartDate: referenceDate.subtract(const Duration(days: 7)),
            plannedGrazingDays: 7,
          ),
        ],
        animals: const [],
        referenceDate: referenceDate,
      );

      expect(dueSoon.active?.remainingGrazingDays, 2);
      expect(dueSoon.active?.isDueSoon, isTrue);
      expect(dueSoon.active?.isDueToday, isFalse);
      expect(dueToday.active?.remainingGrazingDays, 0);
      expect(dueToday.active?.isDueSoon, isFalse);
      expect(dueToday.active?.isDueToday, isTrue);
    });

    test('returns no active paddock when none is in use', () {
      final summary = calculate(
        paddocks: [
          _paddock(id: 'p1', name: 'Norte'),
          _paddock(id: 'p2', name: 'Loma'),
        ],
        animals: [_animal(id: 'a1', paddockId: 'p1')],
        referenceDate: referenceDate,
      );

      expect(summary.active, isNull);
    });

    test('ignores paddocks without rest configuration or valid exit date', () {
      final summary = calculate(
        paddocks: [
          _paddock(id: 'p1', name: 'En uso', status: 'En uso'),
          _paddock(
            id: 'p2',
            name: 'Sin descanso requerido',
            status: 'Descansando',
          ),
          _paddock(
            id: 'p3',
            name: 'Descanso cero',
            status: 'Descansando',
            requiredRestDays: 0,
            lastGrazingEndDate: referenceDate.subtract(const Duration(days: 5)),
          ),
          _paddock(
            id: 'p4',
            name: 'Sin fecha de salida',
            status: 'Descansando',
            requiredRestDays: 20,
          ),
          _paddock(
            id: 'p5',
            name: 'Fecha futura',
            status: 'Descansando',
            requiredRestDays: 20,
            lastGrazingEndDate: referenceDate.add(const Duration(days: 1)),
          ),
        ],
        animals: const [],
        referenceDate: referenceDate,
      );

      expect(summary.next, isNull);
    });

    test('selects the not-ready paddock with the fewest remaining days', () {
      final summary = calculate(
        paddocks: [
          _paddock(id: 'p1', name: 'En uso', status: 'En uso'),
          _paddock(
            id: 'p2',
            name: 'Loma',
            status: 'Descansando',
            requiredRestDays: 20,
            lastGrazingEndDate: referenceDate.subtract(const Duration(days: 8)),
          ),
          _paddock(
            id: 'p3',
            name: 'Bajo',
            status: 'Descansando',
            requiredRestDays: 45,
            lastGrazingEndDate: referenceDate.subtract(
              const Duration(days: 40),
            ),
          ),
        ],
        animals: const [],
        referenceDate: referenceDate,
      );

      expect(summary.next?.paddock.name, 'Bajo');
      expect(summary.next?.elapsedRestDays, 40);
      expect(summary.next?.remainingRestDays, 5);
      expect(summary.next?.isReady, isFalse);
    });

    test('selects a ready paddock before not-ready candidates', () {
      final summary = calculate(
        paddocks: [
          _paddock(id: 'p1', name: 'En uso', status: 'En uso'),
          _paddock(
            id: 'p2',
            name: 'Casi listo',
            status: 'Descansando',
            requiredRestDays: 20,
            lastGrazingEndDate: referenceDate.subtract(
              const Duration(days: 19),
            ),
          ),
          _paddock(
            id: 'p3',
            name: 'Listo',
            status: 'Descansando',
            requiredRestDays: 30,
            lastGrazingEndDate: referenceDate.subtract(
              const Duration(days: 35),
            ),
          ),
        ],
        animals: const [],
        referenceDate: referenceDate,
      );

      expect(summary.next?.paddock.name, 'Listo');
      expect(summary.next?.remainingRestDays, -5);
      expect(summary.next?.isReady, isTrue);
    });

    test('when multiple paddocks are ready, selects the one ready first', () {
      final summary = calculate(
        paddocks: [
          _paddock(id: 'p1', name: 'En uso', status: 'En uso'),
          _paddock(
            id: 'p2',
            name: 'Listo reciente',
            status: 'Descansando',
            requiredRestDays: 30,
            lastGrazingEndDate: referenceDate.subtract(
              const Duration(days: 31),
            ),
          ),
          _paddock(
            id: 'p3',
            name: 'Listo primero',
            status: 'Descansando',
            requiredRestDays: 20,
            lastGrazingEndDate: referenceDate.subtract(
              const Duration(days: 35),
            ),
          ),
        ],
        animals: const [],
        referenceDate: referenceDate,
      );

      expect(summary.next?.paddock.name, 'Listo primero');
      expect(summary.next?.elapsedRestDays, 35);
      expect(summary.next?.remainingRestDays, -15);
    });

    test('uses the configured order after the active paddock', () {
      final summary = calculate(
        paddocks: [
          _paddock(
            id: 'p1',
            name: 'Actual',
            status: 'En uso',
            rotationOrder: 1,
          ),
          _paddock(
            id: 'p2',
            name: 'Siguiente del orden',
            status: 'Descansando',
            rotationOrder: 2,
            requiredRestDays: 30,
            lastGrazingEndDate: referenceDate.subtract(
              const Duration(days: 20),
            ),
          ),
          _paddock(
            id: 'p3',
            name: 'Listo fuera de turno',
            status: 'Descansando',
            rotationOrder: 3,
            requiredRestDays: 20,
            lastGrazingEndDate: referenceDate.subtract(
              const Duration(days: 30),
            ),
          ),
        ],
        animals: const [],
        referenceDate: referenceDate,
      );

      expect(summary.next?.paddock.name, 'Siguiente del orden');
      expect(summary.next?.remainingRestDays, 10);
    });

    test(
      'wraps the configured order and treats available paddocks as ready',
      () {
        final summary = calculate(
          paddocks: [
            _paddock(id: 'p1', name: 'Primero', rotationOrder: 1),
            _paddock(
              id: 'p2',
              name: 'Actual',
              status: 'En uso',
              rotationOrder: 2,
            ),
          ],
          animals: const [],
          referenceDate: referenceDate,
        );

        expect(summary.next?.paddock.name, 'Primero');
        expect(summary.next?.remainingRestDays, 0);
        expect(summary.next?.isReady, isTrue);
        expect(summary.next?.hasRestRequirement, isFalse);
      },
    );

    test('skips exhausted paddocks in the configured order', () {
      final summary = calculate(
        paddocks: [
          _paddock(
            id: 'p1',
            name: 'Actual',
            status: 'En uso',
            rotationOrder: 1,
          ),
          _paddock(
            id: 'p2',
            name: 'Agotado',
            status: 'Agotado',
            rotationOrder: 2,
          ),
          _paddock(id: 'p3', name: 'Disponible', rotationOrder: 3),
        ],
        animals: const [],
        referenceDate: referenceDate,
      );

      expect(summary.next?.paddock.name, 'Disponible');
    });
  });

  group('PaddockModel', () {
    test('reads new and legacy rotation fields', () {
      final newPaddock = PaddockModel.fromJson({
        'id': 'p1',
        'name': 'Norte',
        'areaHectares': 4.5,
        'pastureType': 'Rye grass',
        'requiredRestDays': 30,
        'rotationOrder': 2,
        'grazingStartDate': '2026-07-10T00:00:00.000',
        'plannedGrazingDays': 7,
        'status': 'Descansando',
        'lastGrazingEndDate': '2026-06-20T00:00:00.000',
        'createdAt': '2026-06-01T00:00:00.000',
        'updatedAt': '2026-07-01T00:00:00.000',
      });

      final legacyPaddock = PaddockModel.fromJson({
        'id': 'p2',
        'name': 'Bajo',
        'areaHectares': 3.2,
        'grassType': 'Kikuyo',
        'status': 'Disponible',
        'lastUsedAt': '2026-06-25T00:00:00.000',
        'createdAt': '2026-06-01T00:00:00.000',
        'updatedAt': '2026-07-01T00:00:00.000',
      });

      expect(newPaddock.pastureType, 'Rye grass');
      expect(newPaddock.requiredRestDays, 30);
      expect(newPaddock.rotationOrder, 2);
      expect(newPaddock.grazingStartDate, DateTime(2026, 7, 10));
      expect(newPaddock.plannedGrazingDays, 7);
      expect(newPaddock.lastGrazingEndDate, DateTime(2026, 6, 20));
      expect(legacyPaddock.pastureType, 'Kikuyo');
      expect(legacyPaddock.lastGrazingEndDate, DateTime(2026, 6, 25));
    });

    test('writes new rotation fields while keeping legacy aliases', () {
      final paddock = _paddock(
        id: 'p1',
        name: 'Norte',
        pastureType: 'Rye grass',
        requiredRestDays: 30,
        rotationOrder: 2,
        grazingStartDate: DateTime(2026, 7, 10),
        plannedGrazingDays: 7,
        lastGrazingEndDate: DateTime(2026, 6, 20),
      );

      final json = PaddockModel.toJson(paddock);

      expect(json['pastureType'], 'Rye grass');
      expect(json['grassType'], 'Rye grass');
      expect(json['requiredRestDays'], 30);
      expect(json['rotationOrder'], 2);
      expect(json['grazingStartDate'], '2026-07-10T00:00:00.000');
      expect(json['plannedGrazingDays'], 7);
      expect(json['lastGrazingEndDate'], '2026-06-20T00:00:00.000');
      expect(json['lastUsedAt'], '2026-06-20T00:00:00.000');
    });
  });
}

Paddock _paddock({
  required String id,
  required String name,
  String status = 'Disponible',
  String? pastureType = 'Rye grass',
  int? requiredRestDays,
  int? rotationOrder,
  DateTime? grazingStartDate,
  int? plannedGrazingDays,
  DateTime? lastGrazingEndDate,
}) {
  final now = DateTime(2026, 7, 1);

  return Paddock(
    id: id,
    name: name,
    areaHectares: 1,
    pastureType: pastureType,
    requiredRestDays: requiredRestDays,
    rotationOrder: rotationOrder,
    grazingStartDate: grazingStartDate,
    plannedGrazingDays: plannedGrazingDays,
    status: status,
    lastGrazingEndDate: lastGrazingEndDate,
    createdAt: now,
    updatedAt: now,
  );
}

Animal _animal({required String id, String? paddockId}) {
  final now = DateTime(2026, 7, 1);

  return Animal(
    id: id,
    code: id,
    type: 'Vaca',
    breed: 'Holstein',
    sex: 'Hembra',
    paddockId: paddockId,
    createdAt: now,
    updatedAt: now,
  );
}
