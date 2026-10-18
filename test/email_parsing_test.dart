import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/core/email_content_helper.dart';
import 'package:espo_worker_app/models/email.dart';

void main() {
  group('Email Parser & Primus Helper Tests', () {
    test('EmailContentHelper decodes common German and HTML entities', () {
      const htmlText = 'Hallo &auml;&ouml;&uuml;&szlig; &amp; &quot;Test&quot; &#39;Single&#39; 100 &euro;';
      final decoded = EmailContentHelper.decodeHtmlEntities(htmlText);
      expect(decoded, 'Hallo äöüß & "Test" \'Single\' 100 €');
    });

    test('htmlToPlainText strips tags and preserves readability', () {
      const html = '''
        <html>
          <head><style>p { color: red; }</style></head>
          <body>
            <h2>Schichtbestätigung</h2>
            <p>Hallo Herr Mustermann,<br>hiermit bestätigen wir Ihren Einsatz.</p>
            <div>Treffpunkt: Haupttor</div>
          </body>
        </html>
      ''';

      final plain = EmailContentHelper.htmlToPlainText(html);
      expect(plain.contains('<style>'), isFalse);
      expect(plain.contains('<h2>'), isFalse);
      expect(plain.contains('Schichtbestätigung'), isTrue);
      expect(plain.contains('Treffpunkt: Haupttor'), isTrue);
    });

    test('sanitizeHtmlForTheme removes dangerous tags and adapts for dark theme', () {
      const raw = '''
        <!DOCTYPE html>
        <html>
          <head><script>alert("evil");</script></head>
          <body>
            <span style="color: #000000; background-color: #ffffff;">Wichtiger Hinweis</span>
          </body>
        </html>
      ''';

      final sanitized = EmailContentHelper.sanitizeHtmlForTheme(raw, isDark: true);
      expect(sanitized.contains('<script>'), isFalse);
      expect(sanitized.contains('color: #F3F4F6;'), isTrue);
      expect(sanitized.contains('background-color: transparent;'), isTrue);
    });

    test('splitEmail splits messageBody and signature with legal disclaimer', () {
      const emailWithSig = '''
Lieber Kollege,

bitte morgen 30 Minuten früher vor Ort sein.

Mit freundlichen Grüßen
Max Einsatzleiter
MB Security Concept & Consulting GmbH

Diese E-Mail und ihre Anhänge sind nur für den aufgeführten Empfänger bestimmt und enthalten vertrauliche Informationen.
''';

      final result = EmailContentHelper.splitEmail(emailWithSig);
      expect(result.hasSignature, isTrue);
      expect(result.messageBody.contains('bitte morgen 30 Minuten früher'), isTrue);
      expect(result.messageBody.contains('Mit freundlichen Grüßen'), isFalse);
      expect(result.signatureBody, isNotNull);
      expect(result.signatureBody!.contains('Max Einsatzleiter'), isTrue);
      expect(result.legalDisclaimer, isNotNull);
      expect(result.legalDisclaimer!.contains('Diese E-Mail und ihre Anhänge sind nur'), isTrue);
    });

    test('Email model computed properties work correctly', () {
      final email = Email(
        id: 'email-1',
        name: 'Einsatzbesprechung Samstag',
        fromString: 'planung@mb-scc.de',
        fromName: 'MB-SCC Disposition',
        dateSent: '2026-10-18 09:30:00',
        bodyPlain: 'Hallo Team, anbei der Ablauf.',
        attachments: [
          EmailAttachment(id: 'att-1', name: 'Dienstplan.pdf', type: 'application/pdf', size: 1048576),
          EmailAttachment(id: 'att-2', name: 'Lageplan.png', type: 'image/png', size: 524288),
        ],
      );

      expect(email.displaySender, 'MB-SCC Disposition');
      expect(email.from, 'planung@mb-scc.de');
      expect(email.displayDate, contains('18.10.2026'));
      expect(email.cleanPlainText, 'Hallo Team, anbei der Ablauf.');
      expect(email.attachments.length, 2);
      expect(email.attachments[0].isPdf, isTrue);
      expect(email.attachments[0].formattedSize, '1.0 MB');
      expect(email.attachments[1].isImage, isTrue);
      expect(email.attachments[1].formattedSize, '512.0 KB');
      expect(email.matchesSearch('Dienstplan'), isTrue);
    });
  });
}
