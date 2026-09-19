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
  String? _myUserName;
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
      _myUserName = user['user']['name'];
    }

    await _loadMessages();
    await _apiService.markChatRoomRead(widget.room.id);
    
    // Poll every 4 seconds for new messages
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) => _loadMessages(silent: true));
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
      // Find the last real message from server that has a valid createdAt
      for (int i = _messages.length - 1; i >= 0; i--) {
        if (!_messages[i].id.startsWith('temp_') && _messages[i].createdAt != null) {
          afterParam = _messages[i].createdAt;
          break;
        }
      }
    }
    
    final msgs = await _apiService.getChatMessages(widget.room.id, after: afterParam);
    
    if (mounted) {
      setState(() {
        if (silent) {
          if (msgs.isNotEmpty) {
            final existingIds = _messages.map((m) => m.id).toSet();
            final newMsgs = <ChatMessage>[];
            
            for (final m in msgs) {
              if (existingIds.contains(m.id)) continue;
              
              // Check if this incoming message replaces a pending temp message
              final tempIndex = _messages.indexWhere(
                (temp) => temp.id.startsWith('temp_') && temp.body == m.body && temp.createdById == m.createdById,
              );
              if (tempIndex != -1) {
                _messages[tempIndex] = m;
              } else {
                newMsgs.add(m);
              }
            }
            
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
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final nowIso = DateTime.now().toUtc().toIso8601String();
    
    // Optimistic UI update
    final tempMsg = ChatMessage(
      id: tempId,
      body: text,
      chatRoomId: widget.room.id,
      createdById: _myUserId,
      createdByName: _myUserName ?? 'Ich',
      createdAt: nowIso,
    );
    
    setState(() {
      _messages.add(tempMsg);
    });
    _scrollToBottom();

    final sentMsg = await _apiService.sendChatMessage(widget.room.id, text);
    if (mounted) {
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (sentMsg != null) {
          if (idx != -1) {
            _messages[idx] = sentMsg;
          } else {
            _messages.add(sentMsg);
          }
        } else {
          if (idx != -1) {
            _messages.removeAt(idx);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fehler beim Senden der Nachricht.')),
          );
        }
      });
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
        parentType: 'ChatMessage',
      );
      
      if (id != null) {
        final sentMsg = await _apiService.sendChatMessage(widget.room.id, '📷 Bild', attachmentId: id);
        if (sentMsg != null) {
          setState(() {
            _messages.add(sentMsg);
          });
          _scrollToBottom();
        } else {
          _loadMessages(silent: true);
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Upload.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = widget.room.getDisplayName(_myUserId, _myUserName);
    final subtitleText = widget.room.type == 'direct'
        ? widget.room.partnerCompany
        : '${widget.room.members.length} Mitglieder';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: widget.room.type == 'group' ? Colors.orange.shade700 : Theme.of(context).primaryColor,
              child: Icon(
                widget.room.type == 'group' ? Icons.groups_rounded : Icons.person_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitleText != null && subtitleText.isNotEmpty)
                    Text(
                      subtitleText,
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'Noch keine Nachrichten vorhanden.\nSchreibe die erste Nachricht!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg.createdById == _myUserId;
                          
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8, top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe 
                                    ? Theme.of(context).primaryColor 
                                    : (isDark ? const Color(0xFF262A33) : Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(16).copyWith(
                                  bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(16),
                                  bottomLeft: !isMe ? const Radius.circular(2) : const Radius.circular(16),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isMe && widget.room.type == 'group' && msg.createdByName != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4.0),
                                      child: Text(
                                        msg.createdByName!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.amberAccent : Theme.of(context).primaryColor,
                                        ),
                                      ),
                                    ),
                                  if (msg.attachmentId != null) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: _ChatImage(
                                          attachmentId: msg.attachmentId!,
                                          isImage: msg.attachmentType?.startsWith('image/') ?? true,
                                        ),
                                      ),
                                    ),
                                  ],
                                  Text(
                                    msg.body,
                                    style: TextStyle(
                                      color: isMe 
                                          ? Colors.white 
                                          : (isDark ? Colors.white : Colors.black87), 
                                      fontSize: 15,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        _formatTimestamp(msg.createdAt),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isMe 
                                              ? Colors.white70 
                                              : (isDark ? Colors.white60 : Colors.black45),
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          msg.id.startsWith('temp_') ? Icons.access_time_rounded : Icons.done_all_rounded,
                                          size: 13,
                                          color: msg.isRead ? Colors.greenAccent : Colors.white70,
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
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2127) : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.camera_alt_rounded, color: Theme.of(context).primaryColor),
                    tooltip: 'Foto aufnehmen',
                    onPressed: _isSending ? null : () => _pickAndSendImage(ImageSource.camera),
                  ),
                  IconButton(
                    icon: Icon(Icons.photo_library_rounded, color: Theme.of(context).primaryColor),
                    tooltip: 'Bild aus Galerie',
                    onPressed: _isSending ? null : () => _pickAndSendImage(ImageSource.gallery),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Nachricht schreiben...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF2C3038) : Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _isSending 
                    ? const SizedBox(width: 40, height: 40, child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
                    : CircleAvatar(
                        radius: 20,
                        backgroundColor: Theme.of(context).primaryColor,
                        child: IconButton(
                          icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                          onPressed: _sendMessage,
                        ),
                      ),
                ],
              ),
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
  final String attachmentId;
  final bool isImage;
  const _ChatImage({required this.attachmentId, this.isImage = true});
  @override
  State<_ChatImage> createState() => _ChatImageState();
}

class _ChatImageState extends State<_ChatImage> {
  Map<String, String>? _headers;
  late final String _url;
  
  @override
  void initState() {
    super.initState();
    _url = '${ServerConfig().apiUrl}/Attachment/file/${widget.attachmentId}';
    SecureStorageService().getToken().then((t) {
      if (mounted) {
        setState(() {
          if (t != null) {
            _headers = t.startsWith('ApiKey ') ? {'X-Api-Key': t.split(' ')[1]} : {'Authorization': t};
          } else {
            _headers = {};
          }
        });
      }
    });
  }
  
  void _showFullScreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                _url,
                headers: _headers ?? {},
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, size: 60, color: Colors.grey),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_headers == null) {
      return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
    }
    return GestureDetector(
      onTap: () => _showFullScreen(context),
      child: Hero(
        tag: 'chat_att_${widget.attachmentId}',
        child: Image.network(
          _url, 
          headers: _headers!,
          fit: BoxFit.cover,
          height: 180,
          width: double.infinity,
          errorBuilder: (_, __, ___) => Container(
            height: 120,
            color: Colors.grey.shade800,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_not_supported_rounded, size: 36, color: Colors.white54),
                  SizedBox(height: 4),
                  Text('Bild konnte nicht geladen werden', style: TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
