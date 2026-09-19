import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:espo_worker_app/models/slot.dart';

void main() {
  group('Dashboard Redesign - Hours & Upcoming Logic Tests', () {
    final format = DateFormat('yyyy-MM-dd HH:mm:ss');
    final String myId = 'angestellte-001';

    // Helper to simulate hours calculation
    Map<String, double> calculateMonthlyHours({
      required List<Slot> slots,
      required String angestellteId,
      required DateTime month,
      DateTime? nowReference,
    }) {
      final now = nowReference ?? DateTime.now();
      double geleistet = 0.0;
      double geplant = 0.0;

      for (final slot in slots) {
        if (slot.angestellteId != angestellteId) continue;
        if (slot.status == 'Storniert' || slot.status == 'Abgesagt' || slot.annahmeStatus == 'Abgelehnt') {
          continue;
        }
        if (slot.dateStart == null || slot.dateEnd == null) continue;

        try {
          final start = format.parseUtc(slot.dateStart!).toLocal();
          final end = format.parseUtc(slot.dateEnd!).toLocal();

          if (start.year != month.year || start.month != month.month) {
            continue;
          }

          double hours = 0.0;
          if (slot.stundenanzahl != null && slot.stundenanzahl! > 0) {
            hours = slot.stundenanzahl!;
          } else {
            hours = end.difference(start).inMinutes / 60.0;
          }

          final bool isGeleistet = (slot.checkout != null && slot.checkout!.isNotEmpty) ||
              slot.status == 'Durchgeführt' ||
              end.isBefore(now);

          if (isGeleistet) {
            geleistet += hours;
          } else {
            geplant += hours;
          }
        } catch (_) {}
      }

      return {
        'geleistet': geleistet,
        'geplant': geplant,
        'gesamt': geleistet + geplant,
      };
    }

    // Helper to simulate upcoming shifts filtering
    List<Slot> filterUpcomingSlots({
      required List<Slot> slots,
      required String angestellteId,
      DateTime? nowReference,
    }) {
      final now = nowReference ?? DateTime.now();

      final filtered = slots.where((slot) {
        if (slot.angestellteId != angestellteId) return false;
        if (slot.status == 'Storniert' || slot.status == 'Abgesagt' || slot.annahmeStatus == 'Abgelehnt') {
          return false;
        }
        if (slot.dateEnd == null) return false;
        try {
          final end = format.parseUtc(slot.dateEnd!).toLocal();
          return end.isAfter(now);
        } catch (_) {
          return false;
        }
      }).toList();

      filtered.sort((a, b) {
        try {
          final aStart = format.parseUtc(a.dateStart!).toLocal();
          final bStart = format.parseUtc(b.dateStart!).toLocal();
          return aStart.compareTo(bStart);
        } catch (_) {
          return 0;
        }
      });

      return filtered;
    }

    test('calculates geleistete, geplante, and gesamtstunden accurately for given month', () {
      final now = DateTime(2026, 9, 19, 14, 0, 0); // Simulated "now": 19.09.2026 14:00
      final targetMonth = DateTime(2026, 9, 1);

      final testSlots = [
        // 1. Past shift, completed (Geleistet = 8.0h)
        Slot(
          id: 's1',
          name: 'Schicht 1',
          status: 'Durchgeführt',
          angestellteId: myId,
          dateStart: '2026-09-01 06:00:00',
          dateEnd: '2026-09-01 14:00:00',
          stundenanzahl: 8.0,
        ),
        // 2. Past shift, checked out (Geleistet = 6.5h)
        Slot(
          id: 's2',
          name: 'Schicht 2',
          status: 'Geplant',
          angestellteId: myId,
          dateStart: '2026-09-10 08:00:00',
          dateEnd: '2026-09-10 14:30:00',
          stundenanzahl: 6.5,
          checkout: '2026-09-10 14:32:00',
        ),
        // 3. Past shift, not checked out but end is before now (Geleistet = 4.0h)
        Slot(
          id: 's3',
          name: 'Schicht 3',
          status: 'Geplant',
          angestellteId: myId,
          dateStart: '2026-09-15 08:00:00',
          dateEnd: '2026-09-15 12:00:00',
          stundenanzahl: 4.0,
        ),
        // 4. Future shift (Geplant = 10.0h)
        Slot(
          id: 's4',
          name: 'Schicht 4',
          status: 'Geplant',
          angestellteId: myId,
          dateStart: '2026-09-22 08:00:00',
          dateEnd: '2026-09-22 18:00:00',
          stundenanzahl: 10.0,
        ),
        // 5. Future shift (Geplant = 5.0h)
        Slot(
          id: 's5',
          name: 'Schicht 5',
          status: 'Geplant',
          angestellteId: myId,
          dateStart: '2026-09-25 10:00:00',
          dateEnd: '2026-09-25 15:00:00',
          stundenanzahl: 5.0,
        ),
        // 6. Cancelled shift (Should NOT count)
        Slot(
          id: 's6',
          name: 'Schicht 6 Storniert',
          status: 'Storniert',
          angestellteId: myId,
          dateStart: '2026-09-20 08:00:00',
          dateEnd: '2026-09-20 16:00:00',
          stundenanzahl: 8.0,
        ),
        // 7. Another employee's shift (Should NOT count)
        Slot(
          id: 's7',
          name: 'Fremde Schicht',
          status: 'Geplant',
          angestellteId: 'other-user',
          dateStart: '2026-09-21 08:00:00',
          dateEnd: '2026-09-21 16:00:00',
          stundenanzahl: 8.0,
        ),
        // 8. Next month shift (October 2026, should NOT count in September)
        Slot(
          id: 's8',
          name: 'Oktober Schicht',
          status: 'Geplant',
          angestellteId: myId,
          dateStart: '2026-10-05 08:00:00',
          dateEnd: '2026-10-05 16:00:00',
          stundenanzahl: 8.0,
        ),
      ];

      final res = calculateMonthlyHours(
        slots: testSlots,
        angestellteId: myId,
        month: targetMonth,
        nowReference: now,
      );

      // Geleistet: 8.0 + 6.5 + 4.0 = 18.5
      expect(res['geleistet'], equals(18.5));
      // Geplant: 10.0 + 5.0 = 15.0
      expect(res['geplant'], equals(15.0));
      // Gesamt: 18.5 + 15.0 = 33.5
      expect(res['gesamt'], equals(33.5));
    });

    test('filters and orders upcoming shifts chronologically', () {
      final now = DateTime(2026, 9, 19, 14, 0, 0);

      final testSlots = [
        Slot(
          id: 's_past',
          name: 'Past Shift',
          status: 'Durchgeführt',
          angestellteId: myId,
          dateStart: '2026-09-18 08:00:00',
          dateEnd: '2026-09-18 16:00:00',
        ),
        Slot(
          id: 's_future2',
          name: 'Shift on 25th',
          status: 'Geplant',
          angestellteId: myId,
          dateStart: '2026-09-25 08:00:00',
          dateEnd: '2026-09-25 16:00:00',
        ),
        Slot(
          id: 's_future1',
          name: 'Shift on 21st',
          status: 'Geplant',
          angestellteId: myId,
          dateStart: '2026-09-21 08:00:00',
          dateEnd: '2026-09-21 16:00:00',
        ),
        Slot(
          id: 's_cancelled',
          name: 'Cancelled Shift',
          status: 'Abgesagt',
          angestellteId: myId,
          dateStart: '2026-09-22 08:00:00',
          dateEnd: '2026-09-22 16:00:00',
        ),
      ];

      final upcoming = filterUpcomingSlots(
        slots: testSlots,
        angestellteId: myId,
        nowReference: now,
      );

      expect(upcoming.length, equals(2));
      expect(upcoming[0].id, equals('s_future1')); // 21st comes before 25th
      expect(upcoming[1].id, equals('s_future2'));
    });
  });
}
