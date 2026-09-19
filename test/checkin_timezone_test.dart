import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/utils/espo_date.dart';

void main() {
  group('EspoDate Timezone & Checkin Tests', () {
    test('formatUtcToLocalTime parses UTC string correctly into local HH:mm', () {
      // 12:00:00 UTC
      final utcStr = '2026-09-19 12:00:00';
      final localTime = formatUtcToLocalTime(utcStr);
      expect(localTime, isNotNull);

      // Verify that local time is equal to DateTime.parse(utcStr).toLocal()
      final expectedLocal = DateTime.utc(2026, 9, 19, 12, 0, 0).toLocal();
      final expectedHHmm = '${expectedLocal.hour.toString().padLeft(2, '0')}:${expectedLocal.minute.toString().padLeft(2, '0')}';
      expect(localTime, equals(expectedHHmm));
    });

    test('formatUtcToLocalTime handles null and empty gracefully', () {
      expect(formatUtcToLocalTime(null), isNull);
      expect(formatUtcToLocalTime(''), isNull);
      expect(formatUtcToLocalTime('   '), isNull);
    });

    test('formatLocalToUtcDateTime converts local HH:mm back to UTC', () {
      final baseDateUtc = '2026-09-19 10:00:00';
      final localHHmm = '14:30';

      final utcFormatted = formatLocalToUtcDateTime(
        localHHmm: localHHmm,
        baseDateUtc: baseDateUtc,
      );
      expect(utcFormatted, isNotNull);

      // Parsing the resulting UTC string back to local should give 14:30
      final localBack = formatUtcToLocalTime(utcFormatted);
      expect(localBack, equals('14:30'));
    });

    test('isSlotOnLocalDate handles regular daytime shifts', () {
      // Shift on 2026-09-19 from 10:00 UTC to 18:00 UTC
      final startUtc = '2026-09-19 10:00:00';
      final endUtc = '2026-09-19 18:00:00';
      final targetDate = DateTime(2026, 9, 19);

      expect(isSlotOnLocalDate(startUtc, endUtc, targetDate), isTrue);
      expect(isSlotOnLocalDate(startUtc, endUtc, DateTime(2026, 9, 18)), isFalse);
      expect(isSlotOnLocalDate(startUtc, endUtc, DateTime(2026, 9, 20)), isFalse);
    });

    test('isSlotOnLocalDate handles night shifts crossing midnight correctly', () {
      // Suppose night shift starts at 22:00 local time on Sep 19 (e.g. 20:00 UTC)
      // and ends at 06:00 local time on Sep 20 (04:00 UTC)
      final startUtc = '2026-09-19 20:00:00';
      final endUtc = '2026-09-20 04:00:00';

      // Should be active on both Sep 19 and Sep 20
      expect(isSlotOnLocalDate(startUtc, endUtc, DateTime(2026, 9, 19)), isTrue);
      expect(isSlotOnLocalDate(startUtc, endUtc, DateTime(2026, 9, 20)), isTrue);
      expect(isSlotOnLocalDate(startUtc, endUtc, DateTime(2026, 9, 21)), isFalse);
      expect(isSlotOnLocalDate(startUtc, endUtc, DateTime(2026, 9, 18)), isFalse);
    });

    test('isSlotOnLocalDate handles early morning shift starting at 01:00 local (23:00 UTC yesterday)', () {
      // 2026-09-19 23:00:00 UTC is 2026-09-20 01:00:00 in CEST (UTC+2)
      final startUtc = '2026-09-19 23:00:00';
      final endUtc = '2026-09-20 07:00:00';

      // In local time, this shift starts on Sep 20
      final sep20 = DateTime(2026, 9, 20);
      expect(isSlotOnLocalDate(startUtc, endUtc, sep20), isTrue);
    });

    test('espoUtcToLocal correctly parses strings with space, T, and Z', () {
      final utc1 = '2026-09-19 12:00:00';
      final dt1 = espoUtcToLocal(utc1);
      final expected1 = DateTime.utc(2026, 9, 19, 12, 0, 0).toLocal();
      expect(dt1.hour, equals(expected1.hour));

      final utc2 = '2026-09-19T12:00:00';
      final dt2 = espoUtcToLocal(utc2);
      expect(dt2.hour, equals(expected1.hour));

      final utc3 = '2026-09-19T12:00:00Z';
      final dt3 = espoUtcToLocal(utc3);
      expect(dt3.hour, equals(expected1.hour));
    });

    test('espoDateToLocal correctly parses pure date and UTC datetime', () {
      // Pure date string
      final d1 = espoDateToLocal('2026-09-20');
      expect(d1.year, equals(2026));
      expect(d1.month, equals(9));
      expect(d1.day, equals(20));

      // UTC 22:00 on Sep 19 (in UTC+2 / CEST, this is Sep 20 00:00:00)
      final d2 = espoDateToLocal('2026-09-19 22:00:00');
      final expectedDt = DateTime.utc(2026, 9, 19, 22, 0, 0).toLocal();
      expect(d2.day, equals(expectedDt.day));
    });
  });
}
