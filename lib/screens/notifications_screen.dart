import 'package:flutter/material.dart';
import '../models/notification.dart';
import '../services/api_service.dart';
import '../core/constants.dart';
import 'slots_screen.dart';
import 'wachbuch_list_screen.dart';
import 'urlaub_screen.dart';
import 'krankentage_screen.dart';
import 'abwesenheit_screen.dart';
import 'meeting_list_screen.dart';

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
    
    // Optimistic UI update
    setState(() {
      _notifications = _notifications.map((n) {
        if (n.id == notif.id) {
          return EspoNotification(
            id: n.id,
            number: n.number,
            type: n.type,
            read: true,
            createdAt: n.createdAt,
            data: n.data,
            noteData: n.noteData,
            message: n.message,
            relatedType: n.relatedType,
          );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Benachrichtigungen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchNotifications,
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const Center(child: Text('Keine Benachrichtigungen gefunden.'))
              : ListView.builder(
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
                            notif.type == 'EmailReceived' ? Icons.email :
                            notif.type == 'Note' ? Icons.note :
                            Icons.notifications,
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
    );
  }

  void _navigateToRelated(EspoNotification notif) {
    // Determine the type of object this notification relates to
    String? type = notif.relatedType;
    String? parentType;
    
    if (notif.noteData != null) {
      parentType = notif.noteData!['parentType'];
    } else if (notif.data.containsKey('parentType')) {
      parentType = notif.data['parentType'];
    }

    // If it's a generic "Note", we want to navigate to the parent (e.g. Slot or CWachbuch)
    if ((type == 'Note' || type == null) && parentType != null) {
      type = parentType;
    }

    // Determine the correct ID to navigate to
    String? entityId = notif.data['parentId'] ?? notif.data['id'];
    if (entityId == null && notif.noteData != null) {
      entityId = notif.noteData!['parentId'] ?? notif.noteData!['id'];
    }

    debugPrint('Notification clicked: Type=$type, Parent=$parentType, ID=$entityId');

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Level 2: Typ=$type, ID=$entityId (Keys=${notif.data.keys.join(', ')})'),
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.blueGrey,
        ),
      );
    }

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
      case 'urlaub':
      case 'urlaube':
        target = const UrlaubScreen();
        break;
      case 'ckrankentage':
      case 'krankentage':
      case 'krankheit':
        target = const KrankentageScreen();
        break;
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
    }

    if (target != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => target!),
      );
    }
  }
}
