import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';

DateTime calendarDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);

class PaddockOperationalStatus {
  const PaddockOperationalStatus._({
    required this.effectiveStatus,
    required this.canReceiveAnimals,
    required this.elapsedRestDays,
    required this.remainingRestDays,
    required this.isRestComplete,
    required this.hasValidRestPlan,
  });

  final String effectiveStatus;
  final bool canReceiveAnimals;
  final int? elapsedRestDays;
  final int? remainingRestDays;
  final bool isRestComplete;
  final bool hasValidRestPlan;

  bool get isReady => isRestComplete;
  bool get hasRestPlan => hasValidRestPlan;
  int? get elapsedDays => elapsedRestDays;
  int? get remainingDays => remainingRestDays;

  factory PaddockOperationalStatus.calculate(
    Paddock paddock, {
    required DateTime referenceDate,
  }) {
    if (paddock.status == 'Agotado') {
      return const PaddockOperationalStatus._(
        effectiveStatus: 'Agotado',
        canReceiveAnimals: false,
        elapsedRestDays: null,
        remainingRestDays: null,
        isRestComplete: false,
        hasValidRestPlan: false,
      );
    }
    if (paddock.status == 'En uso') {
      return const PaddockOperationalStatus._(
        effectiveStatus: 'En uso',
        canReceiveAnimals: true,
        elapsedRestDays: null,
        remainingRestDays: null,
        isRestComplete: false,
        hasValidRestPlan: false,
      );
    }

    final requiredDays = paddock.requiredRestDays;
    final endDate = paddock.lastGrazingEndDate;
    final reference = calendarDate(referenceDate);
    final end = endDate == null ? null : calendarDate(endDate);
    final hasValidPlan =
        requiredDays != null &&
        requiredDays > 0 &&
        end != null &&
        !end.isAfter(reference);
    final elapsed = hasValidPlan ? reference.difference(end).inDays : null;
    final remaining = elapsed == null ? null : requiredDays! - elapsed;
    final complete = remaining != null && remaining <= 0;

    if (paddock.status == 'Descansando') {
      return PaddockOperationalStatus._(
        effectiveStatus: complete ? 'Disponible' : 'Descansando',
        canReceiveAnimals: complete,
        elapsedRestDays: elapsed,
        remainingRestDays: remaining,
        isRestComplete: complete,
        hasValidRestPlan: hasValidPlan,
      );
    }

    // Legacy records marked available may still contain an unfinished rest
    // cycle. Valid rest evidence takes precedence over the persisted label.
    final hasPendingRest = hasValidPlan && !complete;
    return PaddockOperationalStatus._(
      effectiveStatus: hasPendingRest ? 'Descansando' : 'Disponible',
      canReceiveAnimals: !hasPendingRest,
      elapsedRestDays: elapsed,
      remainingRestDays: remaining,
      isRestComplete: complete,
      hasValidRestPlan: hasValidPlan,
    );
  }
}
