import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/models/bereitschaft.dart';

void main() {
  group('Bereitschaft Model & Display Tests', () {
    test('parses Bereitschaft JSON correctly with description and allDay', () {
      final json = {
        'id': '6ad9d64febae40a38',
        'name': 'Jan Bereitschaft',
        'status': 'Planned',
        'dateStart': '2026-11-27 23:00:00',
        'dateEnd': '2026-11-29 23:00:00',
        'isAllDay': true,
        'description': 'Wochenend-Rufbereitschaft für Objektnotfälle und Krankmeldungen.',
      };

      final b = Bereitschaft.fromJson(json);

      expect(b.id, equals('6ad9d64febae40a38'));
      expect(b.name, equals('Jan Bereitschaft'));
      expect(b.status, equals('Planned'));
      expect(b.isAllDay, isTrue);
      expect(b.description, equals('Wochenend-Rufbereitschaft für Objektnotfälle und Krankmeldungen.'));
    });

    test('handles fallback when fields are missing', () {
      final json = <String, dynamic>{
        'id': 'test-123',
      };

      final b = Bereitschaft.fromJson(json);

      expect(b.id, equals('test-123'));
      expect(b.name, isEmpty);
      expect(b.status, isEmpty);
      expect(b.dateStart, isNull);
      expect(b.dateEnd, isNull);
      expect(b.isAllDay, isFalse);
      expect(b.description, isNull);
    });

    test('German status translation maps correctly', () {
      String translateStatus(String status) {
        return status == 'Planned'
            ? 'Geplant'
            : (status == 'Held'
                ? 'Durchgeführt'
                : (status == 'Not Held' ? 'Nicht durchgeführt' : status));
      }

      expect(translateStatus('Planned'), equals('Geplant'));
      expect(translateStatus('Held'), equals('Durchgeführt'));
      expect(translateStatus('Not Held'), equals('Nicht durchgeführt'));
      expect(translateStatus('Other'), equals('Other'));
    });
  });
}
