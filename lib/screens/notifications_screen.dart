import 'package:flutter/material.dart';
import '../models/notification.dart';
import '../services/api_service.dart';
import '../widgets/push_settings_sheet.dart';
import 'slots_screen.dart';
import 'wachbuch_list_screen.dart';
import 'urlaub_screen.dart';
import 'krankentage_screen.dart';
import 'abwesenheit_screen.dart';
import 'meeting_list_screen.dart';
import 'email_list_screen.dart';
import 'chat_list_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ApiService _apiService = ApiService();
  List<EspoNotification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() => _isLoading = true);
    final notifications = await _apiService.getNotifications();
    if (mounted) {
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsRead(EspoNotification notif) async {
    if (notif.read) return;
    
    // Optimistic UI update preserving all fields
    setState(() {
      _notifications = _notifications.map((n) {
        if (n.id == notif.id) {
          return n.copyWith(read: true);
        }
        return n;
      }).toList();
    });

    final success = await _apiService.markNotificationRead(notif.id);
    if (!success) {
      // Revert if API call fails
      _fetchNotifications();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Markieren als gelesen')),
        );
      }
    }
  }

  Future<void> _markAllAsRead() async {
    final unreadCount = _notifications.where((n) => !n.read).length;
    if (unreadCount == 0) return;

    setState(() {
      _notifications = _notifications.map((n) => n.copyWith(read: true)).toList();
    });

    final success = await _apiService.markAllNotificationsRead();
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$unreadCount Benachrichtigung(en) als gelesen markiert')),
        );
      }
    } else {
      _fetchNotifications();
    }
  }

  IconData _getNotificationIcon(EspoNotification notif) {
    final type = notif.type.toLowerCase();
    final related = (notif.relatedType ?? notif.data['entityType']?.toString() ?? '').toLowerCase();

    if (type == 'emailreceived' || related == 'email') return Icons.email;
    if (type == 'geburtstag') return Icons.cake;
    if (type == 'message' || type == 'chatmessage' || related == 'chatroom') return Icons.chat;
    if (type == 'slotchange' || related == 'slots' || related == 'slot') return Icons.calendar_month;
    if (related == 'curlaube' || related == 'urlaub') return Icons.beach_access;
    if (related == 'ckrankenscheine' || related == 'ckrankentage' || related == 'krankheit') return Icons.local_hospital;
    if (related == 'cabwesenheitsnotizen' || related == 'abwesenheit') return Icons.event_busy;
    if (related == 'cwachbuch' || related == 'wachbuch') return Icons.menu_book;
    if (related == 'meeting') return Icons.groups;
    if (type == 'note') return Icons.note;
    if (type == 'taskassigned') return Icons.assignment_turned_in;
    return Icons.notifications;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Benachrichtigungen'),
        actions: [
          if (_notifications.any((n) => !n.read))
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Alle als gelesen markieren',
              onPressed: _markAllAsRead,
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Push-Einstellungen',
            onPressed: () => PushSettingsSheet.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchNotifications,
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildPushStatusHeader(),
                Expanded(
                  child: _notifications.isEmpty
                      ? const Center(child: Text('Keine Benachrichtigungen gefunden.'))
                      : RefreshIndicator(
                          onRefresh: _fetchNotifications,
                          child: ListView.builder(
                            itemCount: _notifications.length,
                            itemBuilder: (context, index) {
                              final notif = _notifications[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        elevation: notif.read ? 1 : 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: notif.read ? Colors.transparent : Theme.of(context).colorScheme.secondary.withOpacity(0.5),
                            width: 2,
                          ),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: notif.read ? Colors.grey.shade300 : Theme.of(context).colorScheme.secondary.withOpacity(0.2),
                            child: Icon(
                              _getNotificationIcon(notif),
                              color: notif.read ? Colors.grey.shade600 : Theme.of(context).primaryColor,
                            ),
                          ),
                          title: Text(
                            notif.title,
                            style: TextStyle(
                              fontWeight: notif.read ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(notif.body),
                                const SizedBox(height: 6),
                                Text(
                                  notif.createdAt,
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          onTap: () {
                            _markAsRead(notif);
                            _navigateToRelated(notif);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildPushStatusHeader() {
    final primaryColor = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryColor.withOpacity(0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_active, color: primaryColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Push-Benachrichtigungen',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Status, Token & Test-Push verwalten',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => PushSettingsSheet.show(context),
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Öffnen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 1,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToRelated(EspoNotification notif) {
    // Determine the type of object this notification relates to
    String? type = notif.relatedType;
    String? parentType;
    
    if (notif.noteData != null) {
      parentType = notif.noteData!['parentType'];
    } else if (notif.data.containsKey('parentType')) {
      parentType = notif.data['parentType'] as String?;
    } else if (notif.data.containsKey('entityType')) {
      parentType = notif.data['entityType'] as String?;
    }

    // If it's a generic "Note", "RuleNotification" or "SlotChange", prioritize entityType / parentType
    if ((type == 'Note' || type == 'RuleNotification' || type == 'SlotChange' || type == null) && parentType != null) {
      type = parentType;
    }

    // Determine the correct ID to navigate to
    String? entityId = notif.data['entityId'] ?? notif.data['parentId'] ?? notif.data['id'];
    if (entityId == null && notif.noteData != null) {
      entityId = notif.noteData!['parentId'] ?? notif.noteData!['id'];
    }
    if (entityId == null && notif.relatedId != null) {
      entityId = notif.relatedId;
    }

    debugPrint('Notification clicked: Type=$type, Parent=$parentType, ID=$entityId');

    if (type == null) return;
    
    Widget? target;
    final lowerType = type.toLowerCase();
    
    switch (lowerType) {
      case 'cwachbuch':
      case 'wachbuch':
      case 'c_wachbuch':
        target = WachbuchListScreen(highlightId: entityId);
        break;
      case 'slot':
      case 'slots':
      case 'schicht':
      case 'schichten':
        target = SlotsScreen(highlightId: entityId);
        break;
      case 'curlaube':
      case 'urlaub':
      case 'urlaube':
        target = const UrlaubScreen();
        break;
      case 'ckrankenscheine':
      case 'ckrankentage':
      case 'krankentage':
      case 'krankheit':
        target = const KrankentageScreen();
        break;
      case 'cabwesenheitsnotizen':
      case 'cabwesenheitsnotiz':
      case 'abwesenheit':
      case 'abwesenheiten':
        target = const AbwesenheitScreen();
        break;
      case 'meeting':
      case 'meetings':
      case 'besprechung':
      case 'termin':
        target = const MeetingListScreen();
        break;
      case 'emailreceived':
      case 'email':
        target = EmailListScreen(initialEmailId: entityId);
        break;
      case 'chatroom':
      case 'chatmessage':
      case 'message':
        target = ChatListScreen(initialRoomId: entityId);
        break;
    }

    if (target != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => target!),
      );
    }
  }
}
