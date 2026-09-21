import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/models/interne_taetigkeit.dart';

void main() {
  group('InterneTaetigkeit Model Tests', () {
    test('Correctly parses Schultag JSON', () {
      final json = {
        'id': 'it123456789012345',
        'name': '[Schultag] Jan Mustermann - 22.09.2026',
        'typ': 'Schultag',
        'status': 'Geplant',
        'dateStart': '2026-09-22 08:00:00',
        'dateEnd': '2026-09-22 16:00:00',
        'isAllDay': true,
        'pause': 0,
        'stunden': 8.0,
        'ort': 'Berufsschule Hamm',
        'beschreibung': 'Fachtheorie Sicherheit',
        'color': '#0ea5e9',
        'arbeitszeitkonto': true,
        'angestellteId': 'ang123',
        'angestellteName': 'Jan Mustermann',
      };

      final item = InterneTaetigkeit.fromJson(json);

      expect(item.id, 'it123456789012345');
      expect(item.name, '[Schultag] Jan Mustermann - 22.09.2026');
      expect(item.typ, 'Schultag');
      expect(item.status, 'Geplant');
      expect(item.isAllDay, true);
      expect(item.stunden, 8.0);
      expect(item.pause, 0);
      expect(item.ort, 'Berufsschule Hamm');
      expect(item.color, '#0ea5e9');
      expect(item.arbeitszeitkonto, true);
    });

    test('Correctly parses Büroschicht JSON with pause and number parsing', () {
      final json = {
        'id': 'it999',
        'name': '[Büroschicht] Christoph Will - 23.09.2026',
        'typ': 'Büroschicht',
        'status': 'Durchgeführt',
        'dateStart': '2026-09-23 09:00:00',
        'dateEnd': '2026-09-23 17:30:00',
        'isAllDay': false,
        'pause': '30',
        'stunden': '8.0',
        'ort': 'Zentrale',
        'color': '#6366f1',
      };

      final item = InterneTaetigkeit.fromJson(json);

      expect(item.id, 'it999');
      expect(item.typ, 'Büroschicht');
      expect(item.status, 'Durchgeführt');
      expect(item.isAllDay, false);
      expect(item.pause, 30);
      expect(item.stunden, 8.0);
      expect(item.color, '#6366f1');
    });

    test('Falls back to safe defaults when fields are missing', () {
      final json = <String, dynamic>{
        'id': 'it_empty',
      };

      final item = InterneTaetigkeit.fromJson(json);

      expect(item.id, 'it_empty');
      expect(item.name, '');
      expect(item.typ, 'Schultag');
      expect(item.status, 'Geplant');
      expect(item.isAllDay, false);
      expect(item.pause, 0);
      expect(item.stunden, 0.0);
      expect(item.color, '#0ea5e9');
      expect(item.arbeitszeitkonto, true);
    });
  });
}
