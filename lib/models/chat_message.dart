class ChatReaction {
  final String emoji;
  final int count;
  final List<String> userIds;

  ChatReaction({
    required this.emoji,
    required this.count,
    required this.userIds,
  });

  bool hasReacted(String? userId) {
    if (userId == null) return false;
    return userIds.contains(userId);
  }

  factory ChatReaction.fromJson(Map<String, dynamic> json) {
    List<String> uids = [];
    if (json['userIds'] is List) {
      uids = (json['userIds'] as List).map((e) => e.toString()).toList();
    }
    return ChatReaction(
      emoji: json['emoji'] as String? ?? '',
      count: json['count'] is int
          ? json['count'] as int
          : (int.tryParse(json['count']?.toString() ?? '0') ?? 0),
      userIds: uids,
    );
  }
}

class ChatMessage {
  final String id;
  final String body;
  final String chatRoomId;
  final String? createdById;
  final String? createdByName;
  final String? createdAt;
  final bool isRead;
  final bool isDeleted;
  final String? editedAt;
  final String? attachmentId;
  final String? attachmentName;
  final String? attachmentType;
  final Map<String, dynamic>? replyTo;
  final List<ChatReaction> reactions;
  final int readByCount;
  final String? createdByCompany;

  ChatMessage({
    required this.id,
    required this.body,
    required this.chatRoomId,
    this.createdById,
    this.createdByName,
    this.createdAt,
    this.isRead = false,
    this.isDeleted = false,
    this.editedAt,
    this.attachmentId,
    this.attachmentName,
    this.attachmentType,
    this.replyTo,
    this.reactions = const [],
    this.readByCount = 0,
    this.createdByCompany,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    List<ChatReaction> reactionList = [];
    if (json['reactions'] is List) {
      reactionList = (json['reactions'] as List)
          .whereType<Map<String, dynamic>>()
          .map((r) => ChatReaction.fromJson(r))
          .toList();
    }

    return ChatMessage(
      id: json['id'] as String,
      body: json['body'] as String? ?? '',
      chatRoomId: json['chatRoomId'] as String? ?? '',
      createdById: json['createdById'] as String?,
      createdByName: json['createdByName'] as String?,
      createdAt: json['createdAt'] as String?,
      isRead: json['isRead'] == true || json['isRead'] == 'true' || json['isRead'] == 1,
      isDeleted: json['isDeleted'] == true || json['isDeleted'] == 'true' || json['isDeleted'] == 1,
      editedAt: json['editedAt'] as String?,
      attachmentId: json['attachmentId'] as String?,
      attachmentName: json['attachmentName'] as String?,
      attachmentType: json['attachmentType'] as String?,
      replyTo: json['replyTo'] is Map<String, dynamic> ? json['replyTo'] as Map<String, dynamic> : null,
      reactions: reactionList,
      readByCount: json['readByCount'] is int
          ? json['readByCount'] as int
          : (int.tryParse(json['readByCount']?.toString() ?? '0') ?? 0),
      createdByCompany: json['createdByCompany'] as String?,
    );
  }
}
