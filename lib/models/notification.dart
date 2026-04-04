class EspoNotification {
  final String id;
  final int number;
  final String type;
  final bool read;
  final String createdAt;
  final Map<String, dynamic> data;
  final Map<String, dynamic>? noteData;
  final String? message;
  final String? relatedType;

  EspoNotification({
    required this.id,
    required this.number,
    required this.type,
    required this.read,
    required this.createdAt,
    required this.data,
    this.noteData,
    this.message,
    this.relatedType,
  });

  factory EspoNotification.fromJson(Map<String, dynamic> json) {
    return EspoNotification(
      id: json['id'] ?? '',
      number: json['number'] ?? 0,
      type: json['type'] ?? 'Unknown',
      read: json['read'] == true,
      createdAt: json['createdAt'] ?? '',
      data: json['data'] as Map<String, dynamic>? ?? {},
      noteData: json['noteData'] as Map<String, dynamic>?,
      message: json['message'] as String?,
      relatedType: json['relatedType'] as String?,
    );
  }

  String get title {
    if (type == 'EmailReceived') return 'Neue E-Mail';
    if (type == 'Note') return 'Neue Notiz';
    if (type == 'TaskAssigned') return 'Neue Aufgabe zugewiesen';
    if (type == 'EntityFollowed') return 'Neuer Follower';
    return 'Benachrichtigung';
  }

  String get body {
    if (type == 'EmailReceived') {
      final subject = data['emailName'] ?? 'Ohne Betreff';
      final from = data['fromString'] ?? 'Unbekannt';
      return 'Von: $from\nBetreff: $subject';
    }
    
    if (type == 'Note') {
      if (noteData != null) {
        final author = noteData!['createdByName'] ?? 'Jemand';
        String text = noteData!['post'] ?? '';
        final parent = noteData!['parentName'] ?? '';
        final parentType = noteData!['parentType'] ?? '';

        // Smarter content for system notes / updates
        if (text.isEmpty) {
          return '$author hat eine Änderung in $parent ($parentType) vorgenommen.';
        }
        
        // Translate common Espo terminology
        if (text.contains('assigned to')) {
          text = text.replaceAll('assigned to', 'zugewiesen an');
          return '$author: $text (in $parent)';
        }

        if (parentType == 'Slots') {
          return '$author hat Informationen zur Schicht $parent aktualisiert.';
        }

        return '$author hat eine Nachricht in $parent hinterlassen:\n$text';
      }
      return 'Eine neue Notiz wurde geschrieben.';
    }

    if (type == 'TaskAssigned') {
      final taskName = data['taskName'] ?? 'Aufgabe';
      return 'Die Aufgabe "$taskName" wurde dir zugewiesen.';
    }

    return message ?? 'Neue Benachrichtigung auf EspoCRM.';
  }
}
