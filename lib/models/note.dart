class NoteAttachment {
  final String id;
  final String name;
  final String type;

  NoteAttachment({required this.id, required this.name, required this.type});
}

class Note {
  final String id;
  final String? post;
  final String? type;
  final String parentType;
  final String parentId;
  final String? createdById;
  final String? createdByName;
  final String createdAt;
  final List<NoteAttachment> attachments;

  Note({
    required this.id,
    this.post,
    this.type,
    required this.parentType,
    required this.parentId,
    this.createdById,
    this.createdByName,
    required this.createdAt,
    this.attachments = const [],
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    // Parse attachments from the three parallel fields
    final List<NoteAttachment> attachments = [];
    final ids = json['attachmentsIds'];
    final names = json['attachmentsNames'];
    final types = json['attachmentsTypes'];

    if (ids != null && ids is List) {
      for (final id in ids) {
        attachments.add(NoteAttachment(
          id: id.toString(),
          name: names?[id] ?? id.toString(),
          type: types?[id] ?? '',
        ));
      }
    }

    return Note(
      id: json['id'] ?? '',
      post: json['post'],
      type: json['type'],
      parentType: json['parentType'] ?? '',
      parentId: json['parentId'] ?? '',
      createdById: json['createdById'],
      createdByName: json['createdByName'],
      createdAt: json['createdAt'] ?? '',
      attachments: attachments,
    );
  }
}
