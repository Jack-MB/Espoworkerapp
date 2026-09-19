import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/chat_room.dart';
import 'chat_screen.dart';
import 'chat_create_screen.dart';

class ChatListScreen extends StatefulWidget {
  final String? initialRoomId;
  const ChatListScreen({Key? key, this.initialRoomId}) : super(key: key);

  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ApiService _apiService = ApiService();
  List<ChatRoom> _rooms = [];
  bool _isLoading = true;
  Timer? _pollingTimer;
  String? _myUserId;
  String? _myUserName;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
    // Auto-refresh chat list every 8 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (_) => _loadRooms(silent: true));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    final user = await _apiService.getSelfUser();
    if (mounted && user != null && user['user'] != null) {
      _myUserId = user['user']['id'];
      _myUserName = user['user']['name'];
    }
    await _loadRooms();

    if (widget.initialRoomId != null && mounted) {
      final found = _rooms.firstWhere(
        (r) => r.id == widget.initialRoomId,
        orElse: () => ChatRoom(id: widget.initialRoomId!, name: 'Chat', type: 'direct'),
      );
      _openChat(found);
    }
  }

  Future<void> _loadRooms({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final rooms = await _apiService.getMyChatRooms();
    if (mounted) {
      setState(() {
        _rooms = rooms;
        if (!silent) _isLoading = false;
      });
    }
  }

  void _openChat(ChatRoom room) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatScreen(room: room)),
    );
    // Reload rooms to update last message and unread count
    _loadRooms(silent: true);
  }

  void _openCreateChat() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ChatCreateScreen()),
    );
    if (result == true) {
      _loadRooms();
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      String iso = timeStr.replaceAll(' ', 'T');
      if (!iso.endsWith('Z')) iso += 'Z';
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return DateFormat('HH:mm').format(dt);
      } else if (now.difference(dt).inDays == 1 && dt.day == now.day - 1) {
        return 'Gestern';
      }
      return DateFormat('dd.MM.').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Aktualisieren',
            onPressed: () => _loadRooms(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rooms.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Colors.grey.shade500),
                      const SizedBox(height: 16),
                      const Text(
                        'Keine Chats vorhanden',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tippe unten rechts auf das Plus-Symbol,\num einen neuen Chat zu starten.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadRooms(),
                  child: ListView.separated(
                    itemCount: _rooms.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 72,
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                    itemBuilder: (context, index) {
                      final room = _rooms[index];
                      final displayName = room.getDisplayName(_myUserId, _myUserName);
                      final isGroup = room.type == 'group';
                      final hasUnread = room.unreadCount > 0;
                      final timeText = _formatTime(room.lastMessageAt);

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: isGroup ? Colors.orange.shade700 : Theme.of(context).primaryColor,
                          child: Icon(
                            isGroup ? Icons.groups_rounded : Icons.person_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (timeText.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                timeText,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: hasUnread ? Theme.of(context).primaryColor : Colors.grey.shade500,
                                  fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (room.partnerCompany != null && room.partnerCompany!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2.0),
                                  child: Text(
                                    room.partnerCompany!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).primaryColor.withOpacity(0.85),
                                    ),
                                  ),
                                ),
                              Text(
                                room.lastMessageText ?? 'Keine Nachrichten',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: hasUnread 
                                      ? (isDark ? Colors.white : Colors.black87) 
                                      : Colors.grey.shade500,
                                  fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: hasUnread
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade600,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                constraints: const BoxConstraints(minWidth: 20),
                                child: Text(
                                  '${room.unreadCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                        onTap: () => _openChat(room),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateChat,
        icon: const Icon(Icons.chat_rounded, color: Colors.white),
        label: const Text('Neuer Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }
}
