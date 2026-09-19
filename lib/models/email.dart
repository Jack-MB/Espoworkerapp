class EmailAttachment {
  final String id;
  final String name;
  final String? type; // MIME type

  EmailAttachment({required this.id, required this.name, this.type});

  bool get isImage =>
      type != null && (type!.startsWith('image/') || name.toLowerCase().endsWith('.jpg') || name.toLowerCase().endsWith('.png') || name.toLowerCase().endsWith('.jpeg') || name.toLowerCase().endsWith('.gif') || name.toLowerCase().endsWith('.webp'));

  bool get isPdf =>
      type == 'application/pdf' || name.toLowerCase().endsWith('.pdf');
}

class Email {
  final String id;
  final String name; // subject
  final String? fromName;
  final String? fromString;
  final String? to;
  final String? status;
  final String? body;
  final String? bodyPlain;
  final bool isHtml;
  final String? dateSent;
  final String? createdAt;
  final List<EmailAttachment> attachments;

  Email({
    required this.id,
    required this.name,
    this.fromName,
    this.fromString,
    this.to,
    this.status,
    this.body,
    this.bodyPlain,
    this.isHtml = true,
    this.dateSent,
    this.createdAt,
    this.attachments = const [],
  });

  factory Email.fromJson(Map<String, dynamic> json) {
    // Attachments: EspoCRM returns attachmentsIds (List) and attachmentsNames (Map id->name)
    final List<EmailAttachment> attachments = [];
    final ids = json['attachmentsIds'];
    final names = json['attachmentsNames'];
    final types = json['attachmentsTypes']; // may be null

    if (ids is List) {
      for (final id in ids) {
        final idStr = id.toString();
        final name = (names is Map ? names[idStr] : null) as String? ?? idStr;
        final type = (types is Map ? types[idStr] : null) as String?;
        attachments.add(EmailAttachment(id: idStr, name: name, type: type));
      }
    }

    return Email(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Ohne Betreff',
      fromName: json['fromName'] as String?,
      fromString: json['fromString'] as String?,
      to: json['to'] as String?,
      status: json['status'] as String?,
      body: json['body'] as String?,
      bodyPlain: json['bodyPlain'] as String?,
      isHtml: json['isHtml'] == true,
      dateSent: json['dateSent'] as String?,
      createdAt: json['createdAt'] as String?,
      attachments: attachments,
    );
  }
}
