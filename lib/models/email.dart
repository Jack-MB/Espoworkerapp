import '../core/email_content_helper.dart';

/// E-Mail Anhang Modell mit Dateityp-Erkennung und Formatierung
class EmailAttachment {
  final String id;
  final String name;
  final String? type; // MIME type
  final int? size;

  EmailAttachment({
    required this.id,
    required this.name,
    this.type,
    this.size,
  });

  bool get isImage =>
      type != null &&
          (type!.startsWith('image/') ||
              name.toLowerCase().endsWith('.jpg') ||
              name.toLowerCase().endsWith('.png') ||
              name.toLowerCase().endsWith('.jpeg') ||
              name.toLowerCase().endsWith('.gif') ||
              name.toLowerCase().endsWith('.webp'));

  bool get isPdf =>
      type == 'application/pdf' || name.toLowerCase().endsWith('.pdf');

  bool get isDoc =>
      name.toLowerCase().endsWith('.doc') ||
      name.toLowerCase().endsWith('.docx') ||
      name.toLowerCase().endsWith('.xls') ||
      name.toLowerCase().endsWith('.xlsx') ||
      name.toLowerCase().endsWith('.odt') ||
      name.toLowerCase().endsWith('.txt') ||
      name.toLowerCase().endsWith('.csv');

  String get formattedSize {
    if (size == null || size! <= 0) return '';
    if (size! < 1024) return '$size B';
    if (size! < 1024 * 1024) return '${(size! / 1024).toStringAsFixed(1)} KB';
    return '${(size! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Vollständiges E-Mail-Modell (analog zu Primus Tablet Suite)
class Email {
  final String id;
  final String name; // subject
  final String? fromName;
  final String? fromAddress;
  final String? fromString;
  final String? to;
  final String? cc;
  final String? bcc;
  final String? replyToString;
  final String? status;
  final String? body;
  final String? bodyPlain;
  final bool isHtml;
  final bool isRead;
  final String? dateSent;
  final String? createdAt;
  final List<EmailAttachment> attachments;

  // Vorberechnete Cache-Felder für schnelle & saubere Darstellung
  late final String cleanPlainText;
  late final String cleanHtml;
  late final SplitEmailResult splitResult;

  Email({
    required this.id,
    required this.name,
    this.fromName,
    this.fromAddress,
    this.fromString,
    this.to,
    this.cc,
    this.bcc,
    this.replyToString,
    this.status,
    this.body,
    this.bodyPlain,
    this.isHtml = true,
    this.isRead = true,
    this.dateSent,
    this.createdAt,
    this.attachments = const [],
  }) {
    // 1. Clean plain text berechnen
    if (bodyPlain != null && bodyPlain!.trim().isNotEmpty) {
      cleanPlainText = EmailContentHelper.decodeHtmlEntities(bodyPlain!.trim());
    } else if (body != null && body!.isNotEmpty) {
      cleanPlainText = EmailContentHelper.htmlToPlainText(body!);
    } else {
      cleanPlainText = '';
    }

    // 2. Clean HTML berechnen
    if (isHtml && body != null && body!.isNotEmpty) {
      cleanHtml = EmailContentHelper.sanitizeHtmlForTheme(body!);
    } else if (cleanPlainText.isNotEmpty) {
      cleanHtml = '<p>${cleanPlainText.replaceAll('\n', '<br>')}</p>';
    } else {
      cleanHtml = '<p style="color: #999;">Kein Nachrichtentext vorhanden.</p>';
    }

    // 3. Aufteilung in Hauptnachricht und Signatur
    splitResult = EmailContentHelper.splitEmail(
      isHtml && body != null && body!.isNotEmpty ? body! : cleanPlainText,
      isHtml: isHtml,
    );
  }

  factory Email.fromJson(Map<String, dynamic> json) {
    // Attachments: EspoCRM returns attachmentsIds (List) and attachmentsNames (Map id->name)
    final List<EmailAttachment> attachments = [];
    final ids = json['attachmentsIds'];
    final names = json['attachmentsNames'];
    final types = json['attachmentsTypes']; // may be null
    final sizes = json['attachmentsSizes'];

    if (ids is List) {
      for (final id in ids) {
        final idStr = id.toString();
        final name = (names is Map ? names[idStr] : null) as String? ?? idStr;
        final type = (types is Map ? types[idStr] : null) as String?;
        final size = (sizes is Map ? int.tryParse(sizes[idStr]?.toString() ?? '') : null);
        attachments.add(EmailAttachment(id: idStr, name: name, type: type, size: size));
      }
    }

    return Email(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? (json['subject'] as String? ?? 'Ohne Betreff'),
      fromName: json['fromName'] as String?,
      fromAddress: json['fromAddress'] as String? ?? json['from'] as String?,
      fromString: json['fromString'] as String?,
      to: json['to'] as String?,
      cc: json['cc'] as String?,
      bcc: json['bcc'] as String?,
      replyToString: json['replyToString'] as String?,
      status: json['status'] as String?,
      body: json['body'] as String?,
      bodyPlain: json['bodyPlain'] as String?,
      isHtml: json['isHtml'] == true || (json['body'] != null && json['body'].toString().contains('<')),
      isRead: json['isRead'] != false,
      dateSent: json['dateSent'] as String?,
      createdAt: json['createdAt'] as String?,
      attachments: attachments,
    );
  }

  bool get hasAttachment => attachments.isNotEmpty;

  String get from {
    if (fromString != null && fromString!.trim().isNotEmpty) return fromString!;
    if (fromName != null && fromName!.trim().isNotEmpty) {
      if (fromAddress != null && fromAddress!.trim().isNotEmpty) {
        return '$fromName <$fromAddress>';
      }
      return fromName!;
    }
    return fromAddress ?? 'Unbekannter Absender';
  }

  String get displaySender {
    if (fromName != null && fromName!.trim().isNotEmpty) return fromName!;
    if (fromString != null && fromString!.trim().isNotEmpty) {
      final match = RegExp(r'^([^<]+)').firstMatch(fromString!);
      if (match != null && match.group(1)!.trim().isNotEmpty) {
        return match.group(1)!.trim();
      }
      return fromString!;
    }
    return fromAddress ?? 'Unbekannt';
  }

  String get displayDate => EmailContentHelper.formatEmailDate(dateSent ?? createdAt);

  /// Prüft, ob diese E-Mail auf eine Suchanfrage passt (Volltextsuche)
  bool matchesSearch(String query) {
    if (query.trim().isEmpty) return true;
    final q = query.trim().toLowerCase();

    // 1. Betreff
    if (name.toLowerCase().contains(q)) return true;

    // 2. Absender
    if (from.toLowerCase().contains(q)) return true;
    if (displaySender.toLowerCase().contains(q)) return true;

    // 3. Empfänger
    if (to != null && to!.toLowerCase().contains(q)) return true;
    if (cc != null && cc!.toLowerCase().contains(q)) return true;

    // 4. E-Mail Inhalt
    if (cleanPlainText.toLowerCase().contains(q)) return true;
    if (bodyPlain != null && bodyPlain!.toLowerCase().contains(q)) return true;
    if (body != null && body!.toLowerCase().contains(q)) return true;

    // 5. Anhänge
    for (final att in attachments) {
      if (att.name.toLowerCase().contains(q)) return true;
    }

    return false;
  }
}
