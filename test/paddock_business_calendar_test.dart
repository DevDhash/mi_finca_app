import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/services/paddock_operational_status.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  final cases =
      jsonDecode(
            File('test/fixtures/d1_business_calendar.json').readAsStringSync(),
          )
          as List;
  for (final raw in cases) {
    final c = raw as Map<String, dynamic>;
    test(c['name'] as String, () {
      final reference = DateTime.parse(c['reference'] as String);
      final end = c['end'] == null ? null : DateTime.parse(c['end'] as String);
      // Initializes the bundled IANA database without changing device timezone.
      calendarDate(reference);
      for (final location in [
        'America/Lima',
        'America/New_York',
        'Asia/Tokyo',
        'UTC',
      ]) {
        final zone = tz.getLocation(location);
        final p = Paddock(
          id: 'p',
          name: 'p',
          areaHectares: 1,
          status: c['status'] as String,
          requiredRestDays: c['days'] as int?,
          lastGrazingEndDate: end == null
              ? null
              : tz.TZDateTime.from(end, zone),
          createdAt: reference,
          updatedAt: reference,
        );
        final result = PaddockOperationalStatus.calculate(
          p,
          referenceDate: tz.TZDateTime.from(reference, zone),
        );
        expect(result.canReceiveAnimals, c['expected'], reason: location);
      }
    });
  }
  test('native UTC and local representations of an instant agree', () {
    final instant = DateTime.parse('2026-09-13T04:59:59Z');
    expect(calendarDate(instant.toLocal()), calendarDate(instant));
    expect(calendarDate(instant), DateTime.utc(2026, 9, 12));
  });
}
