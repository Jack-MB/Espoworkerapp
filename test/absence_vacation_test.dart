import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/models/angestellte.dart';
import 'package:espo_worker_app/models/urlaub.dart';
import 'package:espo_worker_app/models/krankentage.dart';
import 'package:espo_worker_app/models/abwesenheit.dart';
import 'package:espo_worker_app/utils/espo_date.dart';

void main() {
  group('Absence & Vacation Tests', () {
    test('Angestellte model parses Urlaub & Krankentage fields correctly', () {
      final json = {
        'id': 'test-ang-1',
        'name': 'Max Mustermann',
        'gesamtUrlaub': 30,
        'genommenUrlaub': 12,
        'geplanterUrlaub': 4,
        'restUrlaub': 14,
        'krankentageJahr': 3,
        'gesamtKrankentage': 7,
      };

      final ang = Angestellte.fromJson(json);

      expect(ang.id, 'test-ang-1');
      expect(ang.name, 'Max Mustermann');
      expect(ang.gesamtUrlaub, 30);
      expect(ang.genommenUrlaub, 12);
      expect(ang.geplanterUrlaub, 4);
      expect(ang.restUrlaub, 14);
      expect(ang.krankentageJahr, 3);
      expect(ang.gesamtKrankentage, 7);
    });

    test('Werktage calculation logic (BUrlG 6-day week: Mo-Sa, Sunday excluded)', () {
      int countWerktage(DateTime start, DateTime end) {
        int count = 0;
        DateTime cur = DateTime(start.year, start.month, start.day);
        final last = DateTime(end.year, end.month, end.day);
        while (!cur.isAfter(last)) {
          if (cur.weekday != DateTime.sunday) {
            count++;
          }
          cur = cur.add(const Duration(days: 1));
        }
        return count;
      }

      // Monday to Sunday (7 calendar days -> 6 Werktage)
      final monday = DateTime(2026, 10, 12);
      final sunday = DateTime(2026, 10, 18);
      expect(countWerktage(monday, sunday), 6);
      expect(sunday.difference(monday).inDays + 1, 7);

      // Single day test: Sunday should be 0 Werktage
      expect(countWerktage(sunday, sunday), 0);

      // Single day test: Monday should be 1 Werktag
      expect(countWerktage(monday, monday), 1);

      // Two full weeks (14 calendar days -> 12 Werktage)
      final twoWeeksLater = DateTime(2026, 10, 25);
      expect(countWerktage(monday, twoWeeksLater), 12);
    });

    test('Urlaub model parses dates and calculates display range', () {
      final json = {
        'id': 'u1',
        'name': 'Urlaub Test',
        'status': 'Bestätigt',
        'dateStartDate': '2026-08-10',
        'dateEndDate': '2026-08-15',
        'werktage': 6,
        'kalendertage': 6,
      };

      final urlaub = Urlaub.fromJson(json);
      expect(urlaub.status, 'Bestätigt');
      expect(urlaub.werktage, 6);
      expect(urlaub.kalendertage, 6);
      expect(urlaub.formattedDateRange.contains('10.08.2026'), isTrue);
      expect(urlaub.formattedDateRange.contains('15.08.2026'), isTrue);
    });

    test('Abwesenheit date parsing resilience with espoUtcToLocal', () {
      // Format: YYYY-MM-DD HH:mm:ss
      final dt1 = espoUtcToLocal('2026-10-15 08:30:00');
      expect(dt1, isNotNull);

      // ISO Format with Z
      final dt2 = espoUtcToLocal('2026-10-15T08:30:00Z');
      expect(dt2, isNotNull);

      // Pure date format
      final dt3 = espoDateToLocal('2026-10-15');
      expect(dt3.year, 2026);
      expect(dt3.month, 10);
      expect(dt3.day, 15);
    });
  });
}
