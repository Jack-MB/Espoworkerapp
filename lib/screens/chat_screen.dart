import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';
import '../models/chat_room.dart';
import '../models/chat_message.dart';
import 'package:image_picker/image_picker.dart';
import '../core/server_config.dart';

class ChatScreen extends StatefulWidget {
  final ChatRoom room;

  const ChatScreen({Key? key, required this.room}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _pollingTimer;
  String? _myUserId;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    final user = await _apiService.getSelfUser();
    if (!mounted) return;
    if (user != null && user['user'] != null) {
      _myUserId = user['user']['id'];
    }

    await _loadMessages();
    await _apiService.markChatRoomRead(widget.room.id);
    
    // Poll every 5 seconds for new messages
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadMessages(silent: true));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    
    String? afterParam;
    if (silent && _messages.isNotEmpty) {
      afterParam = _messages.last.createdAt;
    }
    
    final msgs = await _apiService.getChatMessages(widget.room.id, after: afterParam);
    
    if (mounted) {
      setState(() {
        if (silent) {
          if (msgs.isNotEmpty) {
            final existingIds = _messages.map((m) => m.id).toSet();
            final newMsgs = msgs.where((m) => !existingIds.contains(m.id)).toList();
            if (newMsgs.isNotEmpty) {
              _messages.addAll(newMsgs);
            }
          }
        } else {
          _messages = msgs;
        }
        if (!silent) _isLoading = false;
      });
      // Scroll to bottom if we loaded fresh OR if we appended new messages
      if (!silent || (silent && msgs.isNotEmpty)) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          }
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    
    // Optimistic UI update
    final tempMsg = ChatMessage(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      body: text,
      chatRoomId: widget.room.id,
      createdById: _myUserId,
      createdByName: 'Ich',
    );
    
    setState(() {
      _messages.add(tempMsg);
    });
    
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });

    final success = await _apiService.sendChatMessage(widget.room.id, text);
    if (success) {
      _loadMessages(silent: true);
    } else {
      // Show error, maybe remove optimistic message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Senden')));
        _loadMessages(silent: true);
      }
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 75,
      );
      if (file == null) return;
      
      setState(() => _isSending = true);
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last.toLowerCase();
      String mimeType = 'image/jpeg';
      if (ext == 'png') mimeType = 'image/png';
      if (ext == 'gif') mimeType = 'image/gif';
      if (ext == 'webp') mimeType = 'image/webp';
      
      final id = await _apiService.uploadAttachment(
        fileName: file.name,
        mimeType: mimeType,
        bytes: bytes,
      );
      
      if (id != null) {
        await _apiService.sendChatMessage(widget.room.id, '📷 Bild', attachmentId: id);
        _loadMessages(silent: true);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Upload')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(widget.room.type == 'group' ? Icons.group : Icons.person, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.room.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg.createdById == _myUserId;
                      
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8, top: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isMe 
                                ? Theme.of(context).primaryColor 
                                : (Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(16).copyWith(
                              bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                              bottomLeft: !isMe ? const Radius.circular(0) : const Radius.circular(16),
                            ),
                          ),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe && widget.room.type == 'group' && msg.createdByName != null)
                                Text(
                                  msg.createdByName!,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                                ),
                              if (msg.attachmentId != null && msg.attachmentType != null && msg.attachmentType!.startsWith('image/')) ...[
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: _ChatImage(url: '${ServerConfig().baseUrl}/?entryPoint=download&id=${msg.attachmentId}'),
                                  ),
                                ),
                              ],
                              Text(
                                msg.body,
                                style: TextStyle(
                                  color: isMe 
                                      ? Colors.white 
                                      : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87), 
                                  fontSize: 15
                                ),
                              ),
                              // Timestamp + read receipt row
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    _formatTimestamp(msg.createdAt),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isMe ? Colors.white60 : Colors.black38,
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.done_all,
                                      size: 14,
                                      color: msg.isRead ? Colors.greenAccent : Colors.white60,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Theme.of(context).brightness == Brightness.dark ? Colors.black87 : Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.camera_alt, color: Theme.of(context).primaryColor),
                  onPressed: _isSending ? null : () => _pickAndSendImage(ImageSource.camera),
                ),
                IconButton(
                  icon: Icon(Icons.photo, color: Theme.of(context).primaryColor),
                  onPressed: _isSending ? null : () => _pickAndSendImage(ImageSource.gallery),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Nachricht schreiben...',
                      hintStyle: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                _isSending 
                  ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator())
                  : CircleAvatar(
                      backgroundColor: Theme.of(context).primaryColor,
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white),
                        onPressed: _sendMessage,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Formats a UTC ISO timestamp for display in message bubbles.
  /// Today → "HH:mm"
  /// Other days → "dd.MM. HH:mm"
  String _formatTimestamp(String? utcStr) {
    if (utcStr == null || utcStr.isEmpty) return '';
    try {
      String isoStr = utcStr.replaceAll(' ', 'T');
      if (!isoStr.endsWith('Z')) isoStr += 'Z';
      final dt = DateTime.parse(isoStr).toLocal();
      final now = DateTime.now();
      final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      return isToday
          ? DateFormat('HH:mm').format(dt)
          : DateFormat('dd.MM. HH:mm').format(dt);
    } catch (_) {
      return '';
    }
  }
}

class _ChatImage extends StatefulWidget {
  final String url;
  const _ChatImage({required this.url});
  @override
  State<_ChatImage> createState() => _ChatImageState();
}

class _ChatImageState extends State<_ChatImage> {
  Map<String, String>? _headers;
  
  @override
  void initState() {
    super.initState();
    SecureStorageService().getToken().then((t) {
      if (mounted) setState(() => _headers = t != null ? {'Authorization': t} : {});
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (_headers == null) return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
    return Image.network(
      widget.url, 
      headers: _headers!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 50, color: Colors.grey),
    );
  }
}
