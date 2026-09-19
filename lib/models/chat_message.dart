class ChatMessage {
  final String id;
  final String body;
  final String chatRoomId;
  final String? createdById;
  final String? createdByName;
  final String? createdAt;
  final bool isRead;
  final String? attachmentId;
  final String? attachmentName;
  final String? attachmentType;
  final Map<String, dynamic>? replyTo;

  ChatMessage({
    required this.id,
    required this.body,
    required this.chatRoomId,
    this.createdById,
    this.createdByName,
    this.createdAt,
    this.isRead = false,
    this.attachmentId,
    this.attachmentName,
    this.attachmentType,
    this.replyTo,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      body: json['body'] as String? ?? '',
      chatRoomId: json['chatRoomId'] as String? ?? '',
      createdById: json['createdById'] as String?,
      createdByName: json['createdByName'] as String?,
      createdAt: json['createdAt'] as String?,
      isRead: json['isRead'] == true || json['isRead'] == 'true' || json['isRead'] == 1,
      attachmentId: json['attachmentId'] as String?,
      attachmentName: json['attachmentName'] as String?,
      attachmentType: json['attachmentType'] as String?,
      replyTo: json['replyTo'] is Map<String, dynamic> ? json['replyTo'] as Map<String, dynamic> : null,
    );
  }
}
