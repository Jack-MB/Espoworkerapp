import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/models/slot.dart';
import 'package:espo_worker_app/services/location_tracking_service.dart';

void main() {
  group('DGUV V23 Alleinarbeiterschutz - Model Tests', () {
    test('parses Slot with full Alleinarbeit metadata', () {
      final json = {
        'id': 'slot-allein-001',
        'name': 'Zoom Erlebniswelt Nachtschicht',
        'dateStart': '2026-10-24 20:00:00',
        'dateEnd': '2026-10-25 06:00:00',
        'isAlleinarbeit': true,
        'alleinarbeitIntervallMinuten': 15,
        'alleinarbeitConsentAt': '2026-10-24 20:01:05',
        'accountName': 'ZOOM Erlebniswelt Gelsenkirchen',
        'objekteName': 'Revier 1',
      };

      final slot = Slot.fromJson(json);

      expect(slot.id, equals('slot-allein-001'));
      expect(slot.name, equals('Zoom Erlebniswelt Nachtschicht'));
      expect(slot.isAlleinarbeit, isTrue);
      expect(slot.alleinarbeitIntervallMinuten, equals(15));
      expect(slot.alleinarbeitConsentAt, equals('2026-10-24 20:01:05'));
    });

    test('defaults Alleinarbeit to false and 10 minutes when omitted', () {
      final json = {
        'id': 'slot-standard-002',
        'name': 'Pfortendienst Tor 2',
        'dateStart': '2026-10-24 08:00:00',
        'dateEnd': '2026-10-24 16:00:00',
      };

      final slot = Slot.fromJson(json);

      expect(slot.id, equals('slot-standard-002'));
      expect(slot.isAlleinarbeit, isFalse);
      expect(slot.alleinarbeitIntervallMinuten, equals(10));
      expect(slot.alleinarbeitConsentAt, isNull);
    });

    test('copyWith preserves or modifies Alleinarbeit parameters correctly', () {
      final baseSlot = Slot(
        id: 'slot-003',
        name: 'Streifenfahrt',
        status: 'Planned',
        isAlleinarbeit: true,
        alleinarbeitIntervallMinuten: 20,
      );

      expect(baseSlot.isAlleinarbeit, isTrue);
      expect(baseSlot.alleinarbeitIntervallMinuten, equals(20));
      expect(baseSlot.alleinarbeitConsentAt, isNull);

      final updatedSlot = baseSlot.copyWith(
        alleinarbeitConsentAt: '2026-10-24 22:00:00',
      );

      expect(updatedSlot.id, equals('slot-003'));
      expect(updatedSlot.isAlleinarbeit, isTrue);
      expect(updatedSlot.alleinarbeitIntervallMinuten, equals(20));
      expect(updatedSlot.alleinarbeitConsentAt, equals('2026-10-24 22:00:00'));
    });

    test('isNachtschicht correctly identifies night shifts and boundaries', () {
      // 1. Keyword im Namen
      final slotWithName = Slot(
        id: 's1',
        name: 'Streifendienst Nacht',
        status: 'Planned',
      );
      expect(slotWithName.isNachtschicht, isTrue);

      // 2. Start ab 20:00 UTC (in Deutschland >= 21:00 / 22:00 Uhr)
      final slotWithLateHour = Slot(
        id: 's2',
        name: 'Objektschutz Zoom',
        status: 'Planned',
        dateStart: '2026-10-24 20:00:00',
        dateEnd: '2026-10-25 05:00:00',
      );
      expect(slotWithLateHour.isNachtschicht, isTrue);

      // 3. Tagschicht (z. B. 08:00 - 16:30 Uhr)
      final daySlot = Slot(
        id: 's3',
        name: 'Einlasskontrolle Pforte',
        status: 'Planned',
        dateStart: '2026-10-24 07:00:00',
        dateEnd: '2026-10-24 15:30:00',
      );
      expect(daySlot.isNachtschicht, isFalse);
    });

    test('isAlleinarbeitNachtschicht ONLY true for genuine night shifts with activated Alleinarbeit', () {
      // Fall 1: Tagschicht mit versehentlich gesetzter Alleinarbeit -> MUSS FALSE SEIN
      final daySlotWithAllein = Slot(
        id: 's-day-allein',
        name: 'Tagesposten Tor 1',
        status: 'Planned',
        dateStart: '2026-10-24 07:00:00',
        dateEnd: '2026-10-24 15:30:00',
        isAlleinarbeit: true,
      );
      expect(daySlotWithAllein.isAlleinarbeit, isTrue);
      expect(daySlotWithAllein.isNachtschicht, isFalse);
      expect(daySlotWithAllein.isAlleinarbeitNachtschicht, isFalse,
          reason: 'Tagschichten dürfen NIEMALS in den Alleinarbeiterschutz fallen');

      // Fall 2: Nachtschicht OHNE Alleinarbeit -> MUSS FALSE SEIN
      final nightSlotWithoutAllein = Slot(
        id: 's-night-no-allein',
        name: 'Nachtstreife Doppelbesetzung',
        status: 'Planned',
        dateStart: '2026-10-24 20:00:00',
        dateEnd: '2026-10-25 05:00:00',
        isAlleinarbeit: false,
      );
      expect(nightSlotWithoutAllein.isNachtschicht, isTrue);
      expect(nightSlotWithoutAllein.isAlleinarbeit, isFalse);
      expect(nightSlotWithoutAllein.isAlleinarbeitNachtschicht, isFalse,
          reason: 'Nachtschichten ohne explizite Alleinarbeit dürfen nicht getrackt werden');

      // Fall 3: Echte Nachtschicht MIT Alleinarbeit -> MUSS TRUE SEIN
      final nightSlotWithAllein = Slot(
        id: 's-night-allein',
        name: 'Sicherheits-Nachtstreife Zoom',
        status: 'Planned',
        dateStart: '2026-10-24 20:00:00',
        dateEnd: '2026-10-25 05:00:00',
        isAlleinarbeit: true,
      );
      expect(nightSlotWithAllein.isNachtschicht, isTrue);
      expect(nightSlotWithAllein.isAlleinarbeit, isTrue);
      expect(nightSlotWithAllein.isAlleinarbeitNachtschicht, isTrue,
          reason: 'Ausschließlich Nachtschichten mit Alleinarbeit aktivieren den Schutz');
    });

    test('parses isAlleinarbeit flexibly from various JSON representations (bool, int, string)', () {
      expect(Slot.fromJson({'id': '1', 'name': 'S1', 'status': 'P', 'isAlleinarbeit': true}).isAlleinarbeit, isTrue);
      expect(Slot.fromJson({'id': '2', 'name': 'S2', 'status': 'P', 'isAlleinarbeit': 1}).isAlleinarbeit, isTrue);
      expect(Slot.fromJson({'id': '3', 'name': 'S3', 'status': 'P', 'isAlleinarbeit': '1'}).isAlleinarbeit, isTrue);
      expect(Slot.fromJson({'id': '4', 'name': 'S4', 'status': 'P', 'isAlleinarbeit': 'true'}).isAlleinarbeit, isTrue);
      expect(Slot.fromJson({'id': '5', 'name': 'S5', 'status': 'P', 'isAlleinarbeit': false}).isAlleinarbeit, isFalse);
      expect(Slot.fromJson({'id': '6', 'name': 'S6', 'status': 'P', 'isAlleinarbeit': 0}).isAlleinarbeit, isFalse);
    });

    test('requiresAlleinarbeitConsent ONLY prompts when night shift AND Alleinarbeit active AND consent pending', () {
      // 1. Tagschicht mit Alleinarbeit -> KEINE Einwilligung erforderlich
      final dayAllein = Slot(
        id: 'c1',
        name: 'Tagesdienst Pforte',
        status: 'Planned',
        dateStart: '2026-10-24 07:00:00',
        dateEnd: '2026-10-24 16:00:00',
        isAlleinarbeit: true,
      );
      expect(dayAllein.requiresAlleinarbeitConsent, isFalse,
          reason: 'Tagschichten dürfen niemals einen Einwilligungsdialog auslösen');

      // 2. Nachtschicht OHNE Alleinarbeit -> KEINE Einwilligung erforderlich
      final nightNoAllein = Slot(
        id: 'c2',
        name: 'Nachtschicht Team',
        status: 'Planned',
        dateStart: '2026-10-24 21:00:00',
        dateEnd: '2026-10-25 06:00:00',
        isAlleinarbeit: false,
      );
      expect(nightNoAllein.requiresAlleinarbeitConsent, isFalse,
          reason: 'Nachtschichten ohne Alleinarbeit dürfen niemals einen Einwilligungsdialog auslösen');

      // 3. Echte Nachtschicht MIT Alleinarbeit, noch keine Einwilligung -> Einwilligung MUSS gefordert werden
      final nightAlleinNoConsent = Slot(
        id: 'c3',
        name: 'Nachtstreife Allein Zoom',
        status: 'Planned',
        dateStart: '2026-10-24 21:00:00',
        dateEnd: '2026-10-25 06:00:00',
        isAlleinarbeit: true,
        alleinarbeitConsentAt: null,
      );
      expect(nightAlleinNoConsent.requiresAlleinarbeitConsent, isTrue,
          reason: 'Nachtschicht mit aktiver Alleinarbeit erfordert DGUV V23 Einwilligung beim Check-In');

      // 4. Echte Nachtschicht MIT Alleinarbeit, Einwilligung bereits erfolgt -> KEINE erneute Abfrage
      final nightAlleinWithConsent = nightAlleinNoConsent.copyWith(
        alleinarbeitConsentAt: '2026-10-24 21:00:45',
      );
      expect(nightAlleinWithConsent.requiresAlleinarbeitConsent, isFalse,
          reason: 'Nach bereits erfolgter Einwilligung darf beim erneuten Check-In kein Dialog mehr erscheinen');
    });
  });

  group('DGUV V23 LocationTrackingService State Tests', () {
    test('LocationTrackingService is a singleton', () {
      final instance1 = LocationTrackingService();
      final instance2 = LocationTrackingService();

      expect(identical(instance1, instance2), isTrue);
      expect(instance1.isTracking, isFalse);
      expect(instance1.activeSlotId, isNull);
    });

    test('stopTracking cleanly resets tracking state', () {
      final service = LocationTrackingService();
      service.stopTracking();

      expect(service.isTracking, isFalse);
      expect(service.activeSlotId, isNull);
    });
  });
}
