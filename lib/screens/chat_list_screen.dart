import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadRooms();
    if (widget.initialRoomId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openChat(ChatRoom(id: widget.initialRoomId!, name: 'Chat', type: 'direct'));
      });
    }
  }

  Future<void> _loadRooms() async {
    setState(() => _isLoading = true);
    final rooms = await _apiService.getMyChatRooms();
    if (mounted) {
      setState(() {
        _rooms = rooms;
        _isLoading = false;
      });
    }
  }

  void _openChat(ChatRoom room) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatScreen(room: room)),
    );
    // Reload rooms to update last message and unread count
    _loadRooms();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRooms),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rooms.isEmpty
              ? const Center(child: Text('Keine Chats gefunden.'))
              : ListView.builder(
                  itemCount: _rooms.length,
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: room.type == 'group' ? Colors.orange : Theme.of(context).primaryColor,
                        child: Icon(room.type == 'group' ? Icons.group : Icons.person, color: Colors.white),
                      ),
                      title: Text(room.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        room.lastMessageText ?? 'Keine Nachrichten',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: room.unreadCount > 0 ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey.shade500,
                          fontWeight: room.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: room.unreadCount > 0
                          ? Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              child: Text('${room.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            )
                          : null,
                      onTap: () => _openChat(room),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateChat,
        child: const Icon(Icons.add_comment),
        tooltip: 'Neuer Chat',
      ),
    );
  }
}
