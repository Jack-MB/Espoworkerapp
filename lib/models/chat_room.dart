class ChatRoom {
  final String id;
  final String name;
  final String type; // direct, group
  final String? lastMessageText;
  final String? lastMessageAt;
  final String? lastMessageBy;
  final int unreadCount;
  final String? partnerUserId;
  final String? partnerCompany;
  final String? partnerAvatarId;
  final List<Map<String, dynamic>> members;

  ChatRoom({
    required this.id,
    required this.name,
    required this.type,
    this.lastMessageText,
    this.lastMessageAt,
    this.lastMessageBy,
    this.unreadCount = 0,
    this.partnerUserId,
    this.partnerCompany,
    this.partnerAvatarId,
    this.members = const [],
  });

  /// Computes a clean display title:
  /// For 1:1 direct chats, shows the partner's name rather than "User A ↔ User B".
  /// For group chats, shows the group name.
  String getDisplayName(String? currentUserId, String? currentUserName) {
    if (type == 'direct') {
      if (partnerUserId != null && members.isNotEmpty) {
        final partner = members.firstWhere(
          (m) => m['id'] == partnerUserId,
          orElse: () => {},
        );
        if (partner['name'] != null && (partner['name'] as String).trim().isNotEmpty) {
          return partner['name'];
        }
      }
      if (name.contains('↔')) {
        final parts = name.split('↔').map((s) => s.trim()).toList();
        if (parts.length >= 2) {
          if (currentUserName != null && currentUserName.isNotEmpty) {
            if (parts[0].toLowerCase() == currentUserName.toLowerCase()) return parts[1];
            if (parts[1].toLowerCase() == currentUserName.toLowerCase()) return parts[0];
          }
          return parts[1].isNotEmpty ? parts[1] : parts[0];
        }
      }
    }
    return name;
  }

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> parsedMembers = [];
    if (json['members'] is List) {
      for (var item in json['members']) {
        if (item is Map<String, dynamic>) {
          parsedMembers.add(item);
        }
      }
    }

    String? partnerAvatar;
    final partnerId = json['partnerUserId'] as String?;
    if (partnerId != null && parsedMembers.isNotEmpty) {
      final p = parsedMembers.firstWhere(
        (m) => m['id'] == partnerId,
        orElse: () => {},
      );
      partnerAvatar = p['avatarId'] as String?;
    }

    return ChatRoom(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Chat',
      type: json['type'] as String? ?? 'direct',
      lastMessageText: json['lastMessageText'] as String?,
      lastMessageAt: json['lastMessageAt'] as String?,
      lastMessageBy: json['lastMessageBy'] as String?,
      unreadCount: json['unreadCount'] as int? ?? 0,
      partnerUserId: partnerId,
      partnerCompany: json['partnerCompany'] as String?,
      partnerAvatarId: partnerAvatar,
      members: parsedMembers,
    );
  }
}
