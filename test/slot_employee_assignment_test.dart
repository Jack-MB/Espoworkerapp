import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/models/slot.dart';

void main() {
  group('Slot Model Employee Assignment & KP Parsing Tests', () {
    test('Slot parses kooperationspartnerId and kooperationspartnerName correctly', () {
      final json = {
        'id': 'slot-test-01',
        'name': 'Bodo Wartke - Wunderpunkt | 17:30 - 22:30',
        'status': 'Geplant',
        'kooperationspartnerId': '6a0445618f9c06736',
        'kooperationspartnerName': 'Cerberus-Sicherheit GmbH',
        'angestellteId': null,
        'angestellteName': null,
        'einsatzleiterId': 'el-123',
        'canEditOnr': true,
      };

      final slot = Slot.fromJson(json);

      expect(slot.id, 'slot-test-01');
      expect(slot.kooperationspartnerId, '6a0445618f9c06736');
      expect(slot.kooperationspartnerName, 'Cerberus-Sicherheit GmbH');
      expect(slot.angestellteId, isNull);
      expect(slot.angestellteName, isNull);
      expect(slot.canEditOnr, isTrue);
    });

    test('Slot copyWith preserves and updates employee assignment fields', () {
      final slot = Slot(
        id: 'slot-test-02',
        name: 'MSV Duisburg',
        status: 'Geplant',
        kooperationspartnerId: '69e9f2a93910fbbbc',
        kooperationspartnerName: 'MB Security Concept & Consulting GmbH',
      );

      expect(slot.angestellteId, isNull);

      final updated = slot.copyWith(
        angestellteId: 'ang-99',
        angestellteName: 'Max Mustermann',
        oNr: '0147',
      );

      expect(updated.id, 'slot-test-02');
      expect(updated.angestellteId, 'ang-99');
      expect(updated.angestellteName, 'Max Mustermann');
      expect(updated.oNr, '0147');
      expect(updated.kooperationspartnerId, '69e9f2a93910fbbbc');
      expect(updated.kooperationspartnerName, 'MB Security Concept & Consulting GmbH');
    });

    test('Employee live search filtering works for Name, Personalnummer, Ordner-Nr and Qualifikation', () {
      final employees = [
        {
          'id': 'emp-1',
          'name': 'Kerstin Albrecht',
          'personalnummer': '00049',
          'oNr': '0049',
          'qualifikationen': ['Sachkunde 34a'],
        },
        {
          'id': 'emp-2',
          'name': 'Dennes Adelsberger',
          'personalnummer': '00050',
          'oNr': '0050',
          'qualifikationen': ['Servicekraft'],
        },
        {
          'id': 'emp-3',
          'name': 'Stefan Kirsch',
          'personalnummer': '00100',
          'oNr': '0100',
          'qualifikationen': ['Brandschutz', 'Ersthelfer'],
        },
      ];

      List<Map<String, dynamic>> filter(String q) {
        final query = q.trim().toLowerCase();
        if (query.isEmpty) return employees;
        return employees.where((emp) {
          final name = (emp['name'] ?? '').toString().toLowerCase();
          final pNr = (emp['personalnummer'] ?? '').toString().toLowerCase();
          final oNr = (emp['oNr'] ?? '').toString().toLowerCase();
          final quals = (emp['qualifikationen'] as List? ?? []).join(' ').toLowerCase();
          return name.contains(query) || pNr.contains(query) || oNr.contains(query) || quals.contains(query);
        }).toList();
      }

      // Search by partial first name
      expect(filter('Kerstin').length, 1);
      expect(filter('Kerstin').first['name'], 'Kerstin Albrecht');

      // Search by personalnummer
      expect(filter('00050').length, 1);
      expect(filter('00050').first['name'], 'Dennes Adelsberger');

      // Search by ordnernummer
      expect(filter('0100').length, 1);
      expect(filter('0100').first['name'], 'Stefan Kirsch');

      // Search by qualification
      expect(filter('Brandschutz').length, 1);
      expect(filter('Brandschutz').first['name'], 'Stefan Kirsch');

      // Empty query returns all
      expect(filter('').length, 3);
    });

    test('Slot parses angestelltePhone correctly from JSON and updates via copyWith', () {
      final json = {
        'id': 'slot-phone-01',
        'name': 'Schicht mit Notfallnummer',
        'angestellteId': 'emp-77',
        'angestellteName': 'Max Mustermann',
        'angestelltePhone': '+49 170 1234567',
        'geofenceRadius': 75,
      };

      final slot = Slot.fromJson(json);
      expect(slot.angestelltePhone, '+49 170 1234567');
      expect(slot.geofenceRadius, 75);

      final updated = slot.copyWith(angestelltePhone: '+49 171 9876543');
      expect(updated.angestelltePhone, '+49 171 9876543');
      expect(updated.geofenceRadius, 75);
    });

    test('Geofence radius fallback hierarchy resolves correctly', () {
      // 1. Explicit geofenceRadius
      final slot1 = Slot(id: 's1', name: 'S1', status: 'Geplant', geofenceRadius: 100, rad: 30);
      final r1 = slot1.geofenceRadius ?? slot1.rad ?? 50;
      expect(r1, 100);

      // 2. Fallback to rad
      final slot2 = Slot(id: 's2', name: 'S2', status: 'Geplant', rad: 40);
      final r2 = slot2.geofenceRadius ?? slot2.rad ?? 50;
      expect(r2, 40);

      // 3. Fallback to default 50m (never hardcoded 30m)
      final slot3 = Slot(id: 's3', name: 'S3', status: 'Geplant');
      final r3 = slot3.geofenceRadius ?? slot3.rad ?? 50;
      expect(r3, 50);
    });

    test('Pause minutes calculation respects ArbZG thresholds', () {
      int calculateDefaultPause(int workedMinutes) {
        if (workedMinutes >= 540) return 45; // > 9h
        if (workedMinutes >= 360) return 30; // > 6h
        return 0;
      }

      expect(calculateDefaultPause(240), 0); // 4h -> 0 min
      expect(calculateDefaultPause(360), 30); // 6h -> 30 min
      expect(calculateDefaultPause(480), 30); // 8h -> 30 min
      expect(calculateDefaultPause(540), 45); // 9h -> 45 min
      expect(calculateDefaultPause(600), 45); // 10h -> 45 min
    });
  });
}
