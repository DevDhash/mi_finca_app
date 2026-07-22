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
      final active = _paddock(id: 'p1', name: 'Norte', status: 'En uso');
      final summary = calculate(
        paddocks: [
          active,
          _paddock(
            id: 'p2',
            name: 'Loma',
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
          _paddock(id: 'p2', name: 'Sin descanso requerido'),
          _paddock(
            id: 'p3',
            name: 'Descanso cero',
            requiredRestDays: 0,
            lastGrazingEndDate: referenceDate.subtract(const Duration(days: 5)),
          ),
          _paddock(id: 'p4', name: 'Sin fecha de salida', requiredRestDays: 20),
          _paddock(
            id: 'p5',
            name: 'Fecha futura',
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
            requiredRestDays: 20,
            lastGrazingEndDate: referenceDate.subtract(const Duration(days: 8)),
          ),
          _paddock(
            id: 'p3',
            name: 'Bajo',
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
            requiredRestDays: 20,
            lastGrazingEndDate: referenceDate.subtract(
              const Duration(days: 19),
            ),
          ),
          _paddock(
            id: 'p3',
            name: 'Listo',
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
            requiredRestDays: 30,
            lastGrazingEndDate: referenceDate.subtract(
              const Duration(days: 31),
            ),
          ),
          _paddock(
            id: 'p3',
            name: 'Listo primero',
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
  });

  group('PaddockModel', () {
    test('reads new and legacy rotation fields', () {
      final newPaddock = PaddockModel.fromJson({
        'id': 'p1',
        'name': 'Norte',
        'areaHectares': 4.5,
        'pastureType': 'Rye grass',
        'requiredRestDays': 30,
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
        lastGrazingEndDate: DateTime(2026, 6, 20),
      );

      final json = PaddockModel.toJson(paddock);

      expect(json['pastureType'], 'Rye grass');
      expect(json['grassType'], 'Rye grass');
      expect(json['requiredRestDays'], 30);
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
  DateTime? lastGrazingEndDate,
}) {
  final now = DateTime(2026, 7, 1);

  return Paddock(
    id: id,
    name: name,
    areaHectares: 1,
    pastureType: pastureType,
    requiredRestDays: requiredRestDays,
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
