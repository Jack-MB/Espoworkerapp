/// Helper für die Bereinigung, Aufteilung und Darstellung von E-Mail-Inhalten,
/// HTML-Code und Signaturen in der Worker-App (analog zu Primus Tablet Suite).
class SplitEmailResult {
  final String messageBody;
  final String? signatureBody;
  final String? legalDisclaimer;
  final bool hasSignature;
  final bool isHtml;

  const SplitEmailResult({
    required this.messageBody,
    this.signatureBody,
    this.legalDisclaimer,
    this.hasSignature = false,
    this.isHtml = false,
  });
}

class EmailContentHelper {
  /// Dekodiert gängige HTML-Entities
  static String decodeHtmlEntities(String text) {
    return text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&euro;', '€')
        .replaceAll('&copy;', '©')
        .replaceAll('&reg;', '®')
        .replaceAll('&auml;', 'ä')
        .replaceAll('&ouml;', 'ö')
        .replaceAll('&uuml;', 'ü')
        .replaceAll('&Auml;', 'Ä')
        .replaceAll('&Ouml;', 'Ö')
        .replaceAll('&Uuml;', 'Ü')
        .replaceAll('&szlig;', 'ß');
  }

  /// Konvertiert HTML zu lesbarem, sauberem Plain-Text
  static String htmlToPlainText(String html) {
    if (html.isEmpty) return '';

    String cleaned = html;

    // 1. Script- und Style-Blöcke komplett entfernen
    cleaned = cleaned.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?<\/style>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?<\/script>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<head[^>]*>[\s\S]*?<\/head>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    // 2. Zeilenumbruch-Tags
    cleaned = cleaned.replaceAll(RegExp(r'<br\s*[\/]?>', caseSensitive: false), '\n');
    cleaned = cleaned.replaceAll(RegExp(r'<\/p>', caseSensitive: false), '\n\n');
    cleaned = cleaned.replaceAll(RegExp(r'<\/div>', caseSensitive: false), '\n');
    cleaned = cleaned.replaceAll(RegExp(r'<\/tr>', caseSensitive: false), '\n');
    cleaned = cleaned.replaceAll(RegExp(r'<\/li>', caseSensitive: false), '\n');
    cleaned = cleaned.replaceAll(RegExp(r'<td>', caseSensitive: false), '\t');

    // 3. Alle übrigen HTML Tags entfernen
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), '');

    // 4. Entities dekodieren
    cleaned = decodeHtmlEntities(cleaned);

    // 5. Mehrfache Leerzeilen auf maximal 2 reduzieren
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return cleaned.trim();
  }

  /// Bereinigt HTML für die gefahrlose, lesbare Anzeige im Dark-Theme und Standard-Theme
  static String sanitizeHtmlForTheme(String rawHtml, {bool isDark = true}) {
    if (rawHtml.isEmpty) return '';

    String cleaned = rawHtml;

    // Head, Meta, Title, Doctype, Style, Script entfernen
    cleaned = cleaned.replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<head[^>]*>[\s\S]*?<\/head>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?<\/style>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?<\/script>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    // Body Tags extrahieren oder bereinigen
    final bodyMatch = RegExp(r'<body[^>]*>([\s\S]*?)<\/body>', caseSensitive: false).firstMatch(cleaned);
    if (bodyMatch != null && bodyMatch.group(1) != null) {
      cleaned = bodyMatch.group(1)!;
    }

    if (isDark) {
      // Inline Stile säubern, die dunkle Schrift auf dunklem Hintergrund erzwingen
      cleaned = cleaned.replaceAll(
          RegExp(r'color\s*:\s*(#000000|#000|black|#111111|#222222|#333333)\s*;?', caseSensitive: false),
          'color: #F3F4F6;');
      cleaned = cleaned.replaceAll(
          RegExp(r'background-color\s*:\s*(#ffffff|#fff|white)\s*;?', caseSensitive: false),
          'background-color: transparent;');
    }

    return cleaned.trim();
  }

  /// Teilt eine E-Mail in Hauptnachricht und Signatur/Impressum auf
  static SplitEmailResult splitEmail(String content, {bool isHtml = false}) {
    if (content.isEmpty) {
      return const SplitEmailResult(messageBody: '');
    }

    // Bekannte Signatur-Startmarker
    final sigPatterns = [
      r'--\s*$',
      r'Mit freundlichen Grüßen',
      r'Mit Freundlichen Grüßen',
      r'Mit besten Grüßen',
      r'Viele Grüße',
      r'Schöne Grüße',
      r'Herzliche Grüße',
      r'Best JB',
      r'Best regards',
      r'Kind regards',
      r'MB Security Concept & Consulting GmbH',
    ];

    final regexPattern = RegExp('(${sigPatterns.join('|')})', caseSensitive: false, multiLine: true);
    final match = regexPattern.firstMatch(content);

    if (match == null) {
      return SplitEmailResult(
        messageBody: content,
        hasSignature: false,
        isHtml: isHtml,
      );
    }

    final splitIndex = match.start;
    final messageBody = content.substring(0, splitIndex).trim();
    String signatureBlock = content.substring(splitIndex).trim();

    // Rechtshinweis / Compliance-Disclaimer separieren, falls vorhanden
    String? legalDisclaimer;
    final disclaimerPattern = RegExp(
      r'(Diese E-Mail und ihre Anhänge sind nur für den aufgeführten Empfänger bestimmt|This e-mail and its attachments are intended solely|Diese E-Mail enthält vertrauliche|Hinweis: Dieses Dokument wurde maschinell erstellt)',
      caseSensitive: false,
    );
    final discMatch = disclaimerPattern.firstMatch(signatureBlock);
    if (discMatch != null) {
      legalDisclaimer = signatureBlock.substring(discMatch.start).trim();
      signatureBlock = signatureBlock.substring(0, discMatch.start).trim();
    }

    return SplitEmailResult(
      messageBody: messageBody.isEmpty ? content : messageBody,
      signatureBody: signatureBlock.isNotEmpty ? signatureBlock : null,
      legalDisclaimer: legalDisclaimer,
      hasSignature: true,
      isHtml: isHtml,
    );
  }

  /// Formatiert ein Datum lesbar auf Deutsch (z. B. "03.10.2026, 12:52 Uhr")
  static String formatEmailDate(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return '—';
    try {
      final parsed = DateTime.parse(rawDate.replaceFirst(' ', 'T'));
      final d = parsed.day.toString().padLeft(2, '0');
      final m = parsed.month.toString().padLeft(2, '0');
      final y = parsed.year.toString();
      final hh = parsed.hour.toString().padLeft(2, '0');
      final mm = parsed.minute.toString().padLeft(2, '0');
      return '$d.$m.$y $hh:$mm Uhr';
    } catch (_) {
      return rawDate;
    }
  }
}
