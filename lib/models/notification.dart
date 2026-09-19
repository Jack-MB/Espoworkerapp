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
  final String? relatedId;

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
    this.relatedId,
  });

  EspoNotification copyWith({
    String? id,
    int? number,
    String? type,
    bool? read,
    String? createdAt,
    Map<String, dynamic>? data,
    Map<String, dynamic>? noteData,
    String? message,
    String? relatedType,
    String? relatedId,
  }) {
    return EspoNotification(
      id: id ?? this.id,
      number: number ?? this.number,
      type: type ?? this.type,
      read: read ?? this.read,
      createdAt: createdAt ?? this.createdAt,
      data: data ?? this.data,
      noteData: noteData ?? this.noteData,
      message: message ?? this.message,
      relatedType: relatedType ?? this.relatedType,
      relatedId: relatedId ?? this.relatedId,
    );
  }

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
      relatedId: json['relatedId'] as String?,
    );
  }

  String get title {
    if (data['title'] != null && (data['title'] as String).trim().isNotEmpty) {
      return (data['title'] as String).trim();
    }
    if (type == 'EmailReceived') return 'Neue E-Mail';
    if (type == 'Note') return 'Neue Notiz';
    if (type == 'TaskAssigned') return 'Neue Aufgabe zugewiesen';
    if (type == 'EntityFollowed') return 'Neuer Follower';
    if (type.toLowerCase() == 'message') return 'Neue Chat-Nachricht';
    if (type == 'SlotChange') return 'Schicht-Info';
    if (type == 'Geburtstag') return '🎂 Geburtstag';
    return 'Benachrichtigung';
  }

  String get body {
    if (data['body'] != null && (data['body'] as String).trim().isNotEmpty) {
      return (data['body'] as String).trim().replaceAll('**', '');
    }

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

    if (type.toLowerCase() == 'message' && message != null) {
      return message!.replaceAll('**', '');
    }

    if (message != null && message!.isNotEmpty) {
      return message!.replaceAll('**', '');
    }

    return 'Neue Benachrichtigung auf EspoCRM.';
  }
}
