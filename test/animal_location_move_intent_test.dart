import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal_location_move_intent.dart';

void main() {
  test(
    'explicit location intent prevents every form persistence callback',
    () async {
      const intent = AnimalLocationMoveIntent(
        animalId: 'animal',
        expectedFromPaddockId: 'B',
        toPaddockId: 'C',
      );
      var writes = 0;
      await expectLater(
        saveAnimalFormWithoutMove(
          locationIntent: intent,
          persist: () async {
            writes++;
          },
        ),
        throwsA(
          isA<AnimalLocationMoveRequired>().having(
            (e) => e.intent,
            'original intent',
            same(intent),
          ),
        ),
      );
      expect(writes, 0);
    },
  );

  test('explicit unassignment also stops before persistence', () async {
    var writes = 0;
    await expectLater(
      saveAnimalFormWithoutMove(
        locationIntent: const AnimalLocationMoveIntent(
          animalId: 'animal',
          expectedFromPaddockId: 'B',
          toPaddockId: null,
        ),
        persist: () async {
          writes++;
        },
      ),
      throwsA(isA<AnimalLocationMoveRequired>()),
    );
    expect(writes, 0);
  });

  test(
    'absence of explicit move intent keeps existing save behavior',
    () async {
      var writes = 0;
      await saveAnimalFormWithoutMove(
        locationIntent: null,
        persist: () async {
          writes++;
        },
      );
      expect(writes, 1);
    },
  );
}
