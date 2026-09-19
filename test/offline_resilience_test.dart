import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/models/slot.dart';
import 'package:espo_worker_app/models/angestellte.dart';
import 'package:espo_worker_app/models/urlaub.dart';
import 'package:espo_worker_app/models/krankentage.dart';
import 'package:espo_worker_app/models/abwesenheit.dart';
import 'package:espo_worker_app/models/meeting.dart';
import 'package:espo_worker_app/models/bereitschaft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Calendar Event Type-Safe Parsing Tests', () {
    test('Heterogeneous List<dynamic> from Future.wait parses safely via whereType<T>() without throwing TypeError', () {
      // Simulate raw results from Future.wait with heterogeneous and untyped empty lists
      final List<dynamic> results = [
        <dynamic>[
          {'id': 's1', 'name': 'Schicht 1', 'dateStart': '2026-09-19 08:00:00', 'dateEnd': '2026-09-19 16:00:00'},
        ].map((e) => Slot.fromJson(e)).toList(), // List<Slot>
        <dynamic>[].toList(), // untyped List<dynamic> []
        <dynamic>[].toList(), // untyped List<dynamic> []
        <dynamic>[
          {'id': 'a1', 'name': 'Arzttermin', 'dateStart': '2026-09-20 10:00:00', 'dateEnd': '2026-09-20 12:00:00'},
        ].map((e) => Abwesenheit.fromJson(e)).toList(),
        <dynamic>[].toList(),
        <dynamic>[
          {'id': 'b1', 'name': 'Bereitschaft', 'dateStart': '2026-09-21 00:00:00', 'dateEnd': '2026-09-21 23:59:59'},
        ].map((e) => Bereitschaft.fromJson(e)).toList(),
      ];

      // Test safe casting using whereType
      final allSlots = (results[0] is List) ? (results[0] as List).whereType<Slot>().toList() : <Slot>[];
      final allUrlaubs = (results[1] is List) ? (results[1] as List).whereType<Urlaub>().toList() : <Urlaub>[];
      final allKrankentage = (results[2] is List) ? (results[2] as List).whereType<Krankentage>().toList() : <Krankentage>[];
      final allAbwesenheiten = (results[3] is List) ? (results[3] as List).whereType<Abwesenheit>().toList() : <Abwesenheit>[];
      final allMeetings = (results[4] is List) ? (results[4] as List).whereType<Meeting>().toList() : <Meeting>[];
      final allBereitschaften = (results[5] is List) ? (results[5] as List).whereType<Bereitschaft>().toList() : <Bereitschaft>[];

      expect(allSlots.length, equals(1));
      expect(allSlots.first.id, equals('s1'));
      expect(allUrlaubs, isEmpty);
      expect(allKrankentage, isEmpty);
      expect(allAbwesenheiten.length, equals(1));
      expect(allAbwesenheiten.first.id, equals('a1'));
      expect(allMeetings, isEmpty);
      expect(allBereitschaften.length, equals(1));
      expect(allBereitschaften.first.id, equals('b1'));
    });
  });

  group('Master Slot Cache Merging Tests', () {
    test('Merging new slots into master map preserves existing slots from other date ranges', () {
      // Existing master map in local storage (e.g. from last week)
      final Map<String, dynamic> masterMap = {
        'slot_prev': {
          'id': 'slot_prev',
          'name': 'Frühere Schicht',
          'dateStart': '2026-09-10 08:00:00',
          'dateEnd': '2026-09-10 16:00:00',
        },
      };

      // New single-day slice arrives from server (e.g. "Heute")
      final newServerSlice = [
        {
          'id': 'slot_today',
          'name': 'Heutige Schicht',
          'dateStart': '2026-09-19 06:00:00',
          'dateEnd': '2026-09-19 14:00:00',
        },
      ];

      for (var item in newServerSlice) {
        masterMap[item['id']!] = item;
      }

      expect(masterMap.length, equals(2));
      expect(masterMap.containsKey('slot_prev'), isTrue);
      expect(masterMap.containsKey('slot_today'), isTrue);

      final List<Slot> allCached = masterMap.values.map((e) => Slot.fromJson(e as Map<String, dynamic>)).toList();
      expect(allCached.length, equals(2));
    });

    test('Offline filter returns matching date range or falls back gracefully', () {
      final List<Slot> allCached = [
        Slot.fromJson({'id': 's1', 'name': 'Gestern', 'dateStart': '2026-09-18 08:00:00', 'dateEnd': '2026-09-18 16:00:00'}),
        Slot.fromJson({'id': 's2', 'name': 'Heute', 'dateStart': '2026-09-19 08:00:00', 'dateEnd': '2026-09-19 16:00:00'}),
        Slot.fromJson({'id': 's3', 'name': 'Morgen', 'dateStart': '2026-09-20 08:00:00', 'dateEnd': '2026-09-20 16:00:00'}),
      ];

      final today = DateTime(2026, 9, 19);
      final filteredToday = allCached.where((s) {
        if (s.dateStart == null) return false;
        final sDate = DateTime.parse(s.dateStart!.split(' ')[0]);
        return !sDate.isBefore(today) && !sDate.isAfter(today);
      }).toList();

      expect(filteredToday.length, equals(1));
      expect(filteredToday.first.id, equals('s2'));
    });
  });

  group('Angestellte Profile Offline Caching Tests', () {
    test('Angestellte record can be serialized and deserialized from cache without loss', () {
      final rawData = {
        'id': 'ang_123',
        'name': 'Max Mustermann',
        'firstName': 'Max',
        'lastName': 'Mustermann',
        'emailAddress': 'max@example.com',
        'phoneNumber': '+49 170 1234567',
        'personalnummer': 'MB-042',
        'mitarbeiterfotoId': 'foto_999',
      };

      final jsonStr = json.encode(rawData);
      final decoded = json.decode(jsonStr);
      final angestellte = Angestellte.fromJson(decoded);

      expect(angestellte.id, equals('ang_123'));
      expect(angestellte.name, equals('Max Mustermann'));
      expect(angestellte.firstName, equals('Max'));
      expect(angestellte.emailAddress, equals('max@example.com'));
      expect(angestellte.rawData['personalnummer'], equals('MB-042'));
      expect(angestellte.rawData['mitarbeiterfotoId'], equals('foto_999'));
    });
  });

  group('GPS Offline Coordinate Fallback Tests', () {
    test('Fallback to slot direct coordinates when object coords are null', () {
      final slotWithCoords = Slot.fromJson({
        'id': 's_gps',
        'name': 'Objekt Schicht',
        'objekteId': 'obj_1',
        'latk': 52.5200,
        'lonK': 13.4050,
      });

      Map<String, dynamic>? objectCoords; // Simulates offline failure
      final double targetLat = objectCoords?['latk'] ?? slotWithCoords.latk ?? 0.0;
      final double targetLon = objectCoords?['lonK'] ?? slotWithCoords.lonK ?? 0.0;

      expect(targetLat, equals(52.5200));
      expect(targetLon, equals(13.4050));
    });
  });
}
