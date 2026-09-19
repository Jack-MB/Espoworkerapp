import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';
import '../services/secure_storage_service.dart';
import '../models/chat_room.dart';
import '../models/chat_message.dart';
import '../core/server_config.dart';

class ChatScreen extends StatefulWidget {
  final ChatRoom room;

  /// Global tracking of the currently open chat room.
  /// Used to suppress intrusive foreground push notifications.
  static String? currentActiveChatRoomId;

  const ChatScreen({super.key, required this.room});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _pollingTimer;
  Timer? _typingPollTimer;
  DateTime? _lastTypingSentTime;
  List<String> _typingUsers = [];
  int _pollCycleCount = 0;

  String? _myUserId;
  String? _myUserName;

  final List<String> _quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🔥', '🎉', '👏'];

  @override
  void initState() {
    super.initState();
    ChatScreen.currentActiveChatRoomId = widget.room.id;
    WidgetsBinding.instance.addObserver(this);

    _controller.addListener(_onInputChanged);
    _initChat();
  }

  @override
  void dispose() {
    if (ChatScreen.currentActiveChatRoomId == widget.room.id) {
      ChatScreen.currentActiveChatRoomId = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _stopTimers();
    _controller.removeListener(_onInputChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _stopTimers();
    } else if (state == AppLifecycleState.resumed) {
      _startTimers();
      _loadMessages(silent: true);
      _pollTyping();
    }
  }

  void _startTimers() {
    _stopTimers();
    // Message polling every 4 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pollCycleCount++;
      // Every 4 cycles (16s), do a full recent refresh to catch updated reactions & soft-deletions
      final bool fullRefresh = (_pollCycleCount % 4 == 0);
      _loadMessages(silent: true, fullRefresh: fullRefresh);
    });

    // Typing indicator polling every 3 seconds
    _typingPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollTyping());
  }

  void _stopTimers() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _typingPollTimer?.cancel();
    _typingPollTimer = null;
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
    _startTimers();
  }

  void _onInputChanged() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    if (_lastTypingSentTime == null || now.difference(_lastTypingSentTime!) > const Duration(seconds: 3)) {
      _lastTypingSentTime = now;
      _apiService.setChatTyping(widget.room.id);
    }
  }

  Future<void> _pollTyping() async {
    if (!mounted) return;
    try {
      final typers = await _apiService.getChatTyping(widget.room.id);
      if (mounted) {
        setState(() {
          _typingUsers = typers.where((name) => name != _myUserName).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMessages({bool silent = false, bool fullRefresh = false}) async {
    if (!silent) setState(() => _isLoading = true);

    String? afterParam;
    if (silent && !fullRefresh && _messages.isNotEmpty) {
      // Look for the last verified message from server
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
        if (silent && !fullRefresh) {
          if (msgs.isNotEmpty) {
            final existingIds = _messages.map((m) => m.id).toSet();
            final newMsgs = <ChatMessage>[];

            for (final m in msgs) {
              if (existingIds.contains(m.id)) {
                // Update existing message in case reactions or deletion changed
                final idx = _messages.indexWhere((existing) => existing.id == m.id);
                if (idx != -1) _messages[idx] = m;
                continue;
              }

              // Check if incoming message replaces an optimistic temp message
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
          // Full fresh load or periodic resync
          if (_messages.isEmpty || !silent) {
            _messages = msgs;
          } else {
            // Merge recent server state without losing optimistic pending temp messages
            final pendingTemps = _messages.where((m) => m.id.startsWith('temp_')).toList();
            _messages = msgs;
            for (final temp in pendingTemps) {
              if (!_messages.any((m) => m.body == temp.body && m.createdById == temp.createdById)) {
                _messages.add(temp);
              }
            }
          }
        }
        if (!silent) _isLoading = false;
      });

      // Scroll to bottom if we loaded fresh OR if we appended new messages
      if (!silent || (silent && msgs.isNotEmpty && !fullRefresh)) {
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

  Future<void> _pickAndSendFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'csv', 'zip'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      final bytes = picked.bytes;
      if (bytes == null) return;

      setState(() => _isSending = true);
      final ext = (picked.extension ?? '').toLowerCase();
      String mimeType = 'application/octet-stream';
      if (ext == 'pdf') mimeType = 'application/pdf';
      if (ext == 'csv') mimeType = 'text/csv';
      if (ext == 'txt') mimeType = 'text/plain';

      final id = await _apiService.uploadAttachment(
        fileName: picked.name,
        mimeType: mimeType,
        bytes: bytes,
        parentType: 'ChatMessage',
      );

      if (id != null) {
        final sentMsg = await _apiService.sendChatMessage(widget.room.id, '📎 ${picked.name}', attachmentId: id);
        if (sentMsg != null) {
          setState(() {
            _messages.add(sentMsg);
          });
          _scrollToBottom();
        } else {
          _loadMessages(silent: true);
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Hochladen.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _toggleReaction(ChatMessage msg, String emoji) async {
    // Optimistic reaction update
    final existingIdx = _messages.indexWhere((m) => m.id == msg.id);
    if (existingIdx == -1) return;

    final currentReactions = List<ChatReaction>.from(_messages[existingIdx].reactions);
    final reactIdx = currentReactions.indexWhere((r) => r.emoji == emoji);

    if (reactIdx != -1) {
      final r = currentReactions[reactIdx];
      final bool reacted = r.hasReacted(_myUserId);
      final newUsers = List<String>.from(r.userIds);
      if (reacted) {
        newUsers.remove(_myUserId);
      } else if (_myUserId != null) {
        newUsers.add(_myUserId!);
      }
      final newCount = newUsers.length;
      if (newCount > 0) {
        currentReactions[reactIdx] = ChatReaction(emoji: emoji, count: newCount, userIds: newUsers);
      } else {
        currentReactions.removeAt(reactIdx);
      }
    } else if (_myUserId != null) {
      currentReactions.add(ChatReaction(emoji: emoji, count: 1, userIds: [_myUserId!]));
    }

    setState(() {
      _messages[existingIdx] = ChatMessage(
        id: msg.id,
        body: msg.body,
        chatRoomId: msg.chatRoomId,
        createdById: msg.createdById,
        createdByName: msg.createdByName,
        createdAt: msg.createdAt,
        isRead: msg.isRead,
        isDeleted: msg.isDeleted,
        editedAt: msg.editedAt,
        attachmentId: msg.attachmentId,
        attachmentName: msg.attachmentName,
        attachmentType: msg.attachmentType,
        replyTo: msg.replyTo,
        reactions: currentReactions,
        readByCount: msg.readByCount,
        createdByCompany: msg.createdByCompany,
      );
    });

    final updated = await _apiService.toggleChatReaction(msg.id, emoji);
    if (mounted && updated != null) {
      setState(() {
        final reIdx = _messages.indexWhere((m) => m.id == msg.id);
        if (reIdx != -1) {
          _messages[reIdx] = ChatMessage(
            id: msg.id,
            body: msg.body,
            chatRoomId: msg.chatRoomId,
            createdById: msg.createdById,
            createdByName: msg.createdByName,
            createdAt: msg.createdAt,
            isRead: msg.isRead,
            isDeleted: msg.isDeleted,
            editedAt: msg.editedAt,
            attachmentId: msg.attachmentId,
            attachmentName: msg.attachmentName,
            attachmentType: msg.attachmentType,
            replyTo: msg.replyTo,
            reactions: updated,
            readByCount: msg.readByCount,
            createdByCompany: msg.createdByCompany,
          );
        }
      });
    }
  }

  void _showMessageOptions(ChatMessage msg) {
    if (msg.isDeleted) return;

    final isMe = msg.createdById == _myUserId;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E2127) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Emoji Quick Bar
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: _quickEmojis.map((emoji) {
                    final hasReacted = msg.reactions.any((r) => r.emoji == emoji && r.hasReacted(_myUserId));
                    return InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        Navigator.pop(ctx);
                        _toggleReaction(msg, emoji);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: hasReacted
                              ? Theme.of(context).primaryColor.withAlpha(51)
                              : (isDark ? const Color(0xFF2C3038) : Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(20),
                          border: hasReacted
                              ? Border.all(color: Theme.of(context).primaryColor, width: 1.5)
                              : null,
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 24)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Text kopieren'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: msg.body));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('In Zwischenablage kopiert')),
                  );
                },
              ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  title: const Text('Nachricht löschen', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeleteMessage(msg);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteMessage(ChatMessage msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nachricht löschen?'),
        content: const Text(
          'Möchtest du diese Nachricht wirklich löschen? Sie wird für alle Teilnehmer als gelöscht angezeigt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await _apiService.deleteChatMessage(msg.id);
              if (ok && mounted) {
                setState(() {
                  final idx = _messages.indexWhere((m) => m.id == msg.id);
                  if (idx != -1) {
                    _messages[idx] = ChatMessage(
                      id: msg.id,
                      body: '',
                      chatRoomId: msg.chatRoomId,
                      createdById: msg.createdById,
                      createdByName: msg.createdByName,
                      createdAt: msg.createdAt,
                      isRead: msg.isRead,
                      isDeleted: true,
                      reactions: const [],
                    );
                  }
                });
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nachricht konnte nicht gelöscht werden.')),
                );
              }
            },
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
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

                          return _buildMessageItem(context, msg, isMe, isDark);
                        },
                      ),
          ),

          // Typing Indicator Banner
          if (_typingUsers.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: isDark ? const Color(0xFF1E2127) : Colors.grey.shade100,
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_typingUsers.join(', ')} tippt...',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

          // Bottom Input Bar
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
                    tooltip: 'Galerie',
                    onPressed: _isSending ? null : () => _pickAndSendImage(ImageSource.gallery),
                  ),
                  IconButton(
                    icon: Icon(Icons.attach_file_rounded, color: Theme.of(context).primaryColor),
                    tooltip: 'Dokument / PDF',
                    onPressed: _isSending ? null : _pickAndSendFile,
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
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
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

  Widget _buildMessageItem(BuildContext context, ChatMessage msg, bool isMe, bool isDark) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _showMessageOptions(msg),
            child: Container(
              margin: const EdgeInsets.only(bottom: 2, top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: msg.isDeleted
                    ? (isDark ? const Color(0xFF1E2127) : Colors.grey.shade300)
                    : isMe
                        ? Theme.of(context).primaryColor
                        : (isDark ? const Color(0xFF262A33) : Colors.grey.shade200),
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(16),
                  bottomLeft: !isMe ? const Radius.circular(2) : const Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(13),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name in group chats
                  if (!isMe && widget.room.type == 'group' && msg.createdByName != null && !msg.isDeleted)
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

                  // Soft-deleted message representation
                  if (msg.isDeleted)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.block_rounded,
                          size: 14,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Diese Nachricht wurde gelöscht.',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 13,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    // Attachment if present
                    if (msg.attachmentId != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                        child: (msg.attachmentType?.startsWith('image/') ?? true)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: _ChatImage(
                                  attachmentId: msg.attachmentId!,
                                  isImage: true,
                                ),
                              )
                            : _ChatFileCard(
                                attachmentId: msg.attachmentId!,
                                fileName: msg.attachmentName ?? 'Dokument',
                                mimeType: msg.attachmentType ?? 'application/octet-stream',
                              ),
                      ),
                    ],

                    // Message body text
                    if (msg.body.isNotEmpty)
                      Text(
                        msg.body,
                        style: TextStyle(
                          color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87),
                          fontSize: 15,
                          height: 1.3,
                        ),
                      ),
                  ],

                  const SizedBox(height: 4),

                  // Footer: Timestamp, Edited flag & Checkmarks
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (msg.editedAt != null && !msg.isDeleted)
                        Padding(
                          padding: const EdgeInsets.only(right: 4.0),
                          child: Text(
                            '(bearbeitet)',
                            style: TextStyle(
                              fontSize: 9,
                              fontStyle: FontStyle.italic,
                              color: isMe ? Colors.white70 : (isDark ? Colors.white60 : Colors.black45),
                            ),
                          ),
                        ),
                      Text(
                        _formatTimestamp(msg.createdAt),
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe ? Colors.white70 : (isDark ? Colors.white60 : Colors.black45),
                        ),
                      ),
                      if (isMe && !msg.isDeleted) ...[
                        const SizedBox(width: 4),
                        Icon(
                          msg.id.startsWith('temp_') ? Icons.access_time_rounded : Icons.done_all_rounded,
                          size: 13,
                          color: (msg.isRead || msg.readByCount > 0) ? Colors.greenAccent : Colors.white70,
                        ),
                        if (widget.room.type == 'group' && msg.readByCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 2.0),
                            child: Text(
                              '${msg.readByCount}',
                              style: const TextStyle(fontSize: 10, color: Colors.greenAccent),
                            ),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Reaction pills row below bubble
          if (!msg.isDeleted && msg.reactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0, left: 4.0, right: 4.0),
              child: Wrap(
                spacing: 4,
                children: msg.reactions.map((r) {
                  final hasReacted = r.hasReacted(_myUserId);
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _toggleReaction(msg, r.emoji),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasReacted
                            ? Theme.of(context).primaryColor.withAlpha(51)
                            : (isDark ? const Color(0xFF2C3038) : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasReacted ? Theme.of(context).primaryColor : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(r.emoji, style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 3),
                          Text(
                            '${r.count}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: hasReacted ? FontWeight.bold : FontWeight.normal,
                              color: hasReacted
                                  ? Theme.of(context).primaryColor
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimestamp(String? utcStr) {
    if (utcStr == null || utcStr.isEmpty) return '';
    try {
      String isoStr = utcStr.replaceAll(' ', 'T');
      if (!isoStr.endsWith('Z')) isoStr += 'Z';
      final dt = DateTime.parse(isoStr).toLocal();
      final now = DateTime.now();
      final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      return isToday ? DateFormat('HH:mm').format(dt) : DateFormat('dd.MM. HH:mm').format(dt);
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

class _ChatFileCard extends StatefulWidget {
  final String attachmentId;
  final String fileName;
  final String mimeType;

  const _ChatFileCard({
    required this.attachmentId,
    required this.fileName,
    required this.mimeType,
  });

  @override
  State<_ChatFileCard> createState() => _ChatFileCardState();
}

class _ChatFileCardState extends State<_ChatFileCard> {
  bool _isDownloading = false;

  Future<void> _openFile() async {
    setState(() => _isDownloading = true);
    try {
      final token = await SecureStorageService().getToken();
      final url = '${ServerConfig().apiUrl}/Attachment/file/${widget.attachmentId}';
      final headers = token != null
          ? (token.startsWith('ApiKey ') ? {'X-Api-Key': token.split(' ')[1]} : {'Authorization': token})
          : <String, String>{};

      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final localFile = File('${tempDir.path}/${widget.fileName}');
        await localFile.writeAsBytes(response.bodyBytes);
        await OpenFilex.open(localFile.path);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Datei konnte nicht heruntergeladen werden.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler beim Öffnen: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPdf = widget.fileName.toLowerCase().endsWith('.pdf');

    return InkWell(
      onTap: _isDownloading ? null : _openFile,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(26),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _isDownloading
                ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    isPdf ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded,
                    size: 28,
                    color: isPdf ? Colors.redAccent : Colors.white70,
                  ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  const Text('Tippen zum Öffnen', style: TextStyle(fontSize: 10, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
