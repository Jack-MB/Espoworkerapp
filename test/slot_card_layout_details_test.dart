import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/models/slot.dart';

void main() {
  group('Slot Card Layout & Details Tests', () {
    test('Slot with positionsname provides valid position text', () {
      final slot = Slot(
        id: 'slot-pos-1',
        name: 'Schicht Tor Süd',
        status: 'Geplant',
        positionsname: 'Einfahrt P1 Schranke',
        schichtbezeichnung: 'Tor Süd',
        angestellteId: 'emp-101',
        angestellteName: 'Jan Philipp von Czapiewski',
        bewacherID: 'DE-BW-88992',
        kooperationspartnerName: 'Securitas Partner',
        oNr: '42',
      );

      expect(slot.positionsname, 'Einfahrt P1 Schranke');
      expect(slot.angestellteName, 'Jan Philipp von Czapiewski');
      expect(slot.bewacherID, 'DE-BW-88992');
      expect(slot.kooperationspartnerName, 'Securitas Partner');
      expect(slot.oNr, '42');
    });

    test('Slot fallback to schichtbezeichnung when positionsname is null or empty', () {
      final slotWithoutPos = Slot(
        id: 'slot-pos-2',
        name: 'Konzert Einlass',
        status: 'Geplant',
        positionsname: '',
        schichtbezeichnung: 'Gästeeinlass West',
        angestellteId: 'emp-102',
        angestellteName: 'Tasnim Hida',
      );

      final posText = (slotWithoutPos.positionsname != null && slotWithoutPos.positionsname!.trim().isNotEmpty)
          ? slotWithoutPos.positionsname!.trim()
          : (slotWithoutPos.schichtbezeichnung != null && slotWithoutPos.schichtbezeichnung!.trim().isNotEmpty
              ? slotWithoutPos.schichtbezeichnung!.trim()
              : null);

      expect(posText, 'Gästeeinlass West');
    });

    test('Internal employee company fallback correctly resolves MB-SCC GmbH', () {
      final internalSlot = Slot(
        id: 'slot-pos-3',
        name: 'Streife Werksgelände',
        status: 'Geplant',
        angestellteId: 'emp-103',
        angestellteName: 'Max Mustermann',
        isPartner: false,
      );

      final firma = (internalSlot.kooperationspartnerName != null && internalSlot.kooperationspartnerName!.isNotEmpty)
          ? internalSlot.kooperationspartnerName!
          : (internalSlot.isInternalEmployee ? 'MB-SCC GmbH' : 'Keine Angabe');

      expect(firma, 'MB-SCC GmbH');
    });
  });
}
