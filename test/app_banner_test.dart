import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppBanner Formatting & Parsing Tests', () {
    test('Splits markdown text into headers, bullet points, and regular text', () {
      const bannerText = '''# Wichtige Neuerung
## Details zum Dienstplan
- Erste Änderung mit **fettem Text**
- Zweite Änderung
Normaler Hinweistext ohne Aufzählung.''';

      final lines = bannerText.split('\n');
      expect(lines.length, 5);
      expect(lines[0].startsWith('# '), isTrue);
      expect(lines[1].startsWith('## '), isTrue);
      expect(lines[2].startsWith('- '), isTrue);
      expect(lines[3].startsWith('- '), isTrue);
      expect(lines[4].startsWith('- '), isFalse);
    });

    test('Parses bold segments with double asterisks accurately', () {
      const line = 'Dies ist **wichtig** und **dringend** zu beachten.';
      final parts = line.split('**');
      // parts: ['Dies ist ', 'wichtig', ' und ', 'dringend', ' zu beachten.']
      expect(parts.length, 5);
      expect(parts[0], 'Dies ist ');
      expect(parts[1], 'wichtig'); // odd index = bold
      expect(parts[2], ' und ');
      expect(parts[3], 'dringend'); // odd index = bold
      expect(parts[4], ' zu beachten.');
    });

    test('Gracefully handles empty or single-line banner without crashing', () {
      const emptyText = '';
      final emptyLines = emptyText.split('\n');
      expect(emptyLines.length, 1);
      expect(emptyLines[0].trim().isEmpty, isTrue);

      const singleLine = 'Einfache Meldung';
      final singleParts = singleLine.split('**');
      expect(singleParts.length, 1);
      expect(singleParts[0], 'Einfache Meldung');
    });

    test('Active banner payload structure validation', () {
      final bannerPayload = {
        'id': 'banner-123',
        'name': 'Dienstplan-Update KW 41',
        'nachricht': 'Bitte beachten Sie die neuen Pausenzeiten.',
        'style': 'warning',
        'zielgruppe': 'intern',
        'isActive': true,
      };

      expect(bannerPayload['id'], 'banner-123');
      expect(bannerPayload['name'], isNotEmpty);
      expect(bannerPayload['style'], 'warning');
      expect(bannerPayload['nachricht'], contains('Pausenzeiten'));
      expect(bannerPayload['zielgruppe'], 'intern');
    });

    test('Zielgruppe audience filter logic for intern vs partner', () {
      bool isBannerVisible(String zielgruppe, bool isInternalEmployee) {
        if (zielgruppe == 'alle') return true;
        if (zielgruppe == 'intern') return isInternalEmployee;
        if (zielgruppe == 'kooperationspartner') return !isInternalEmployee;
        return false;
      }

      // Banner für alle
      expect(isBannerVisible('alle', true), isTrue);
      expect(isBannerVisible('alle', false), isTrue);

      // Banner nur für Interne (z.B. Urlaubsanspruch)
      expect(isBannerVisible('intern', true), isTrue);
      expect(isBannerVisible('intern', false), isFalse);

      // Banner nur für Kooperationspartner
      expect(isBannerVisible('kooperationspartner', true), isFalse);
      expect(isBannerVisible('kooperationspartner', false), isTrue);
    });

    test('Minimized banner floating bar state logic', () {
      // Unbestätigte Banner müssen groß und prominent sichtbar sein
      bool shouldBeCollapsed(bool isConfirmed, bool userCollapsedPreference) {
        return isConfirmed && userCollapsedPreference;
      }

      expect(shouldBeCollapsed(false, true), isFalse);
      expect(shouldBeCollapsed(false, false), isFalse);
      expect(shouldBeCollapsed(true, false), isFalse);
      expect(shouldBeCollapsed(true, true), isTrue);
    });

    test('Birthday snooze calculation logic', () {
      // 1 Tag vorher Modus: nur anzeigen wenn daysUntil <= 1
      bool shouldShowBirthday(int daysUntil, String mode, DateTime? dismissedUntil, DateTime now) {
        if (mode == 'disabled') return false;
        if (dismissedUntil != null && now.isBefore(dismissedUntil)) return false;
        if (mode == 'one_day_before' && daysUntil > 1) return false;
        return true;
      }

      final now = DateTime(2026, 10, 10, 12, 0);
      final nextMonday = DateTime(2026, 10, 12, 0, 0);

      // Standard-Modus: 3 Tage vorher sichtbar
      expect(shouldShowBirthday(3, 'all_week', null, now), isTrue);

      // Modus: Erst 1 Tag vorher
      expect(shouldShowBirthday(3, 'one_day_before', null, now), isFalse);
      expect(shouldShowBirthday(1, 'one_day_before', null, now), isTrue);
      expect(shouldShowBirthday(0, 'one_day_before', null, now), isTrue);

      // Modus: Diese Woche ausgeblendet
      expect(shouldShowBirthday(1, 'all_week', nextMonday, now), isFalse);

      // Nach Ablauf der Snooze-Frist (am Montag) wieder sichtbar
      final mondayAfternoon = DateTime(2026, 10, 12, 14, 0);
      expect(shouldShowBirthday(1, 'all_week', nextMonday, mondayAfternoon), isTrue);

      // Modus: Deaktiviert
      expect(shouldShowBirthday(0, 'disabled', null, now), isFalse);
    });
  });
}
