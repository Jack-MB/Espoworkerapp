class ChatRoom {
  final String id;
  final String name;
  final String type; // direct, group
  final String? lastMessageText;
  final String? lastMessageAt;
  final String? lastMessageBy;
  final int unreadCount;

  ChatRoom({
    required this.id,
    required this.name,
    required this.type,
    this.lastMessageText,
    this.lastMessageAt,
    this.lastMessageBy,
    this.unreadCount = 0,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Chat',
      type: json['type'] as String? ?? 'direct',
      lastMessageText: json['lastMessageText'] as String?,
      lastMessageAt: json['lastMessageAt'] as String?,
      lastMessageBy: json['lastMessageBy'] as String?,
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }
}
