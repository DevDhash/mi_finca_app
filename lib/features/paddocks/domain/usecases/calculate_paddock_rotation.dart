import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';

class CalculatePaddockRotation {
  const CalculatePaddockRotation();

  PaddockRotationSummary call({
    required List<Paddock> paddocks,
    required List<Animal> animals,
    required DateTime referenceDate,
  }) {
    final activePaddock = _firstWhereOrNull(
      paddocks,
      (paddock) => paddock.status == 'En uso',
    );

    final active = activePaddock == null
        ? null
        : ActivePaddockRotation(
            paddock: activePaddock,
            animalCount: animals
                .where((animal) => animal.paddockId == activePaddock.id)
                .length,
          );

    final candidates =
        paddocks
            .where((paddock) => paddock.status != 'En uso')
            .map(
              (paddock) => NextPaddockRotation.fromPaddock(
                paddock: paddock,
                referenceDate: referenceDate,
              ),
            )
            .whereType<NextPaddockRotation>()
            .toList()
          ..sort(_compareRotationCandidates);

    return PaddockRotationSummary(
      active: active,
      next: candidates.isEmpty ? null : candidates.first,
    );
  }

  int _compareRotationCandidates(NextPaddockRotation a, NextPaddockRotation b) {
    final remaining = a.remainingRestDays.compareTo(b.remainingRestDays);
    if (remaining != 0) return remaining;

    final elapsed = b.elapsedRestDays.compareTo(a.elapsedRestDays);
    if (elapsed != 0) return elapsed;

    return a.paddock.name.compareTo(b.paddock.name);
  }

  T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
    for (final value in values) {
      if (test(value)) return value;
    }

    return null;
  }
}

class PaddockRotationSummary {
  const PaddockRotationSummary({required this.active, required this.next});

  final ActivePaddockRotation? active;
  final NextPaddockRotation? next;
}

class ActivePaddockRotation {
  const ActivePaddockRotation({
    required this.paddock,
    required this.animalCount,
  });

  final Paddock paddock;
  final int animalCount;
}

class NextPaddockRotation {
  const NextPaddockRotation({
    required this.paddock,
    required this.requiredRestDays,
    required this.elapsedRestDays,
    required this.remainingRestDays,
  });

  final Paddock paddock;
  final int requiredRestDays;
  final int elapsedRestDays;
  final int remainingRestDays;

  bool get isReady => remainingRestDays <= 0;

  static NextPaddockRotation? fromPaddock({
    required Paddock paddock,
    required DateTime referenceDate,
  }) {
    final requiredRestDays = paddock.requiredRestDays;
    final lastGrazingEndDate = paddock.lastGrazingEndDate;

    if (requiredRestDays == null ||
        requiredRestDays <= 0 ||
        lastGrazingEndDate == null ||
        lastGrazingEndDate.isAfter(referenceDate)) {
      return null;
    }

    final elapsedRestDays = referenceDate.difference(lastGrazingEndDate).inDays;

    return NextPaddockRotation(
      paddock: paddock,
      requiredRestDays: requiredRestDays,
      elapsedRestDays: elapsedRestDays,
      remainingRestDays: requiredRestDays - elapsedRestDays,
    );
  }
}
