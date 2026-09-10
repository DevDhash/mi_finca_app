import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/services/paddock_operational_status.dart';

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
            grazingStartDate: activePaddock.grazingStartDate,
            plannedGrazingDays: activePaddock.plannedGrazingDays,
            elapsedGrazingDays: _elapsedGrazingDays(
              activePaddock,
              referenceDate,
            ),
          );

    final usesConfiguredOrder =
        activePaddock != null &&
        activePaddock.rotationOrder != null &&
        paddocks.any(
          (paddock) =>
              paddock.status != 'En uso' &&
              paddock.status != 'Agotado' &&
              paddock.rotationOrder != null,
        );

    final nextByOrder = usesConfiguredOrder
        ? _nextByConfiguredOrder(
            paddocks: paddocks,
            activePaddock: activePaddock,
            referenceDate: referenceDate,
          )
        : null;

    final candidates = !usesConfiguredOrder
        ? _fallbackCandidates(paddocks, referenceDate)
        : const <NextPaddockRotation>[];

    return PaddockRotationSummary(
      active: active,
      next: nextByOrder ?? (candidates.isEmpty ? null : candidates.first),
    );
  }

  NextPaddockRotation? _nextByConfiguredOrder({
    required List<Paddock> paddocks,
    required Paddock activePaddock,
    required DateTime referenceDate,
  }) {
    final activeOrder = activePaddock.rotationOrder;
    if (activeOrder == null) return null;

    final orderedPaddocks =
        paddocks
            .where(
              (paddock) =>
                  paddock.status != 'En uso' &&
                  paddock.status != 'Agotado' &&
                  paddock.rotationOrder != null,
            )
            .toList()
          ..sort((a, b) => a.rotationOrder!.compareTo(b.rotationOrder!));

    if (orderedPaddocks.isEmpty) return null;

    final afterActive = orderedPaddocks.where(
      (paddock) => paddock.rotationOrder! > activeOrder,
    );
    final orderedRoute = [
      ...afterActive,
      ...orderedPaddocks.where(
        (paddock) => paddock.rotationOrder! <= activeOrder,
      ),
    ];

    for (final paddock in orderedRoute) {
      final next = NextPaddockRotation.fromPaddock(
        paddock: paddock,
        referenceDate: referenceDate,
      );
      if (next != null) return next;
    }

    return null;
  }

  List<NextPaddockRotation> _fallbackCandidates(
    List<Paddock> paddocks,
    DateTime referenceDate,
  ) {
    return paddocks
        .where(
          (paddock) =>
              paddock.status != 'En uso' && paddock.status != 'Agotado',
        )
        .map(
          (paddock) => NextPaddockRotation.fromPaddock(
            paddock: paddock,
            referenceDate: referenceDate,
          ),
        )
        .whereType<NextPaddockRotation>()
        .toList()
      ..sort(_compareRotationCandidates);
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
    required this.grazingStartDate,
    required this.plannedGrazingDays,
    required this.elapsedGrazingDays,
  });

  final Paddock paddock;
  final int animalCount;
  final DateTime? grazingStartDate;
  final int? plannedGrazingDays;
  final int? elapsedGrazingDays;

  int? get remainingGrazingDays {
    final planned = plannedGrazingDays;
    final elapsed = elapsedGrazingDays;
    if (planned == null || elapsed == null) return null;

    return planned - elapsed;
  }

  bool get hasGrazingPlan =>
      grazingStartDate != null &&
      plannedGrazingDays != null &&
      plannedGrazingDays! > 0 &&
      elapsedGrazingDays != null;

  bool get isOverdue => (remainingGrazingDays ?? 1) < 0;
  bool get isDueToday => remainingGrazingDays == 0;
  bool get isDueSoon {
    final remaining = remainingGrazingDays;
    if (remaining == null) return false;

    return remaining > 0 && remaining <= 2;
  }
}

int? _elapsedGrazingDays(Paddock paddock, DateTime referenceDate) {
  final grazingStartDate = paddock.grazingStartDate;
  if (grazingStartDate == null || grazingStartDate.isAfter(referenceDate)) {
    return null;
  }

  return referenceDate.difference(grazingStartDate).inDays;
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
  bool get hasRestRequirement => requiredRestDays > 0;

  static NextPaddockRotation? fromPaddock({
    required Paddock paddock,
    required DateTime referenceDate,
  }) {
    final operational = PaddockOperationalStatus.calculate(
      paddock,
      referenceDate: referenceDate,
    );
    if (operational.effectiveStatus == 'Disponible' &&
        !operational.hasValidRestPlan) {
      return NextPaddockRotation(
        paddock: paddock,
        requiredRestDays: paddock.requiredRestDays ?? 0,
        elapsedRestDays: 0,
        remainingRestDays: 0,
      );
    }

    final requiredRestDays = paddock.requiredRestDays;
    if (!operational.hasValidRestPlan || requiredRestDays == null) {
      return null;
    }

    final elapsedRestDays = operational.elapsedRestDays!;

    return NextPaddockRotation(
      paddock: paddock,
      requiredRestDays: requiredRestDays,
      elapsedRestDays: elapsedRestDays,
      remainingRestDays: operational.remainingRestDays!,
    );
  }
}
