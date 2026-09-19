import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../core/server_config.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';
import '../services/sync_queue_service.dart';
import '../services/web_push_service.dart';
import '../services/deep_link_service.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../services/acl_service.dart';
import '../widgets/push_settings_sheet.dart';
import 'dart:convert';
import 'self_checkin_screen.dart';
import '../services/location_service.dart';
import 'slots_screen.dart';
import 'wachbuch_list_screen.dart';
import 'urlaub_screen.dart';
import 'krankentage_screen.dart';
import 'document_list_screen.dart';
import 'login_screen.dart';
import 'angestellte_profile_screen.dart';
import 'angestellte_list_screen.dart';
import 'notifications_screen.dart';
import 'abwesenheit_screen.dart';
import 'meeting_list_screen.dart';
import 'email_list_screen.dart';
import 'chat_list_screen.dart';
import 'arbeitszeitkonto_screen.dart';
import '../utils/espo_date.dart';
import 'change_password_screen.dart';

import '../models/slot.dart';
import '../models/urlaub.dart';
import '../models/krankentage.dart';
import '../providers/theme_provider.dart';
import '../models/angestellte.dart';
import '../models/abwesenheit.dart';
import '../models/meeting.dart';
import '../models/bereitschaft.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

class ScheduledEvent {
  final String title;
  final String? subtitle;
  final DateTime from;
  final DateTime to;
  final Color background;
  final bool isAllDay;
  final dynamic originalObject; // Store the actual object (Slot, Urlaub, etc.)

  ScheduledEvent(this.title, {
    this.subtitle, 
    required this.from, 
    required this.to, 
    required this.background, 
    this.isAllDay = false,
    this.originalObject,
  });
}

class EventDataSource extends CalendarDataSource {
  EventDataSource(List<ScheduledEvent> source) {
    appointments = source;
  }

  @override
  DateTime getStartTime(int index) {
    return _getEventData(index).from;
  }

  @override
  DateTime getEndTime(int index) {
    return _getEventData(index).to;
  }

  @override
  String getSubject(int index) {
    return _getEventData(index).title;
  }

  @override
  Color getColor(int index) {
    return _getEventData(index).background;
  }

  @override
  bool isAllDay(int index) {
    return _getEventData(index).isAllDay;
  }

  ScheduledEvent _getEventData(int index) {
    final dynamic event = appointments![index];
    if (event is ScheduledEvent) {
      return event;
    }
    // Fallback if something is wrong
    return ScheduledEvent('Unbekannt', from: DateTime.now(), to: DateTime.now(), background: Colors.grey);
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  final AclService _aclService = AclService();
  final SecureStorageService _storage = SecureStorageService();
  CalendarView _calendarView = CalendarView.month;
  final CalendarController _calendarController = CalendarController();
  
  String _username = '';
  String? _angestellteId;
  int _unreadCount = 0;
  int _chatUnreadCount = 0;
  Angestellte? _angestellte;
  String? _authToken;

  Future<List<ScheduledEvent>> _eventsFuture = Future.value([]);

  // Dashboard & Monatsübersicht State
  int _selectedTab = 0; // 0 = Dashboard, 1 = Kalender
  DateTime _selectedMonth = DateTime.now();
  List<Slot> _rawSlots = [];

  static const List<String> _monthNames = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
  ];
  static const List<String> _dayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  // Check-in state for calendar
  final SyncQueueService _syncQueue = SyncQueueService();
  Set<String> _checkedSlotIds = {};
  Set<String> _checkedSlotOutIds = {};
  Map<String, String> _checkedSlotTimes = {};
  Map<String, String> _checkedSlotOutTimes = {};
  
  // Filter settings
  bool _showSlots = true;
  bool _showUrlaub = true;
  bool _showKrank = true;
  bool _showAbwesenheit = true;
  bool _showMeetings = true;
  bool _persistFilters = false;

  // Counts for filters
  int _countSlots = 0;
  int _countUrlaub = 0;
  int _countKrank = 0;
  int _countAbwesenheit = 0;
  int _countMeetings = 0;
  bool? _serverOnline;
  String _pushPermission = 'granted';
  List<Map<String, dynamic>> _upcomingBirthdays = [];
  bool _birthdaysDismissed = false;
  int _pendingQueueCount = 0;

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Run initialization sequentially to prevent race conditions
    _initializeDashboard();

    // Start sync queue for calendar check-ins & Wachbuch notes
    _syncQueue.startPeriodicSync();
    _syncQueue.addListener(_onSyncQueueChanged);
    _syncQueue.getPendingCount().then((count) {
      if (mounted) setState(() => _pendingQueueCount = count);
    });

    // FCM Token Sync beim Start
    _syncFcmTokenOnStart();

    // Setup push click & URL hash deep linking to slots
    _setupDeepLink();

    // Start 60-second periodic unread notification polling
    _startUnreadNotificationPolling();
  }

  Future<void> _initializeDashboard() async {
    try {
      await _loadPreferences();
      await _loadLocalCheckins();
      await _checkServerStatus();
      await _loadUser();
      await _fetchUnread();
      await _loadUpcomingBirthdays();
    } catch (e) {
      debugPrint('Dashboard: Error during initialization: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        // Start fetching calendar events only after core services are ready
        _refreshEvents();
        // Admin banner
        _loadAdminBanner();
      }
    }
  }

  Future<void> _loadAdminBanner() async {
    final banner = await _apiService.getActiveBanner();
    if (mounted && banner != null) {
      // Kurze Verzögerung damit das UI fertig gerendert ist
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) _showAdminBannerDialog(banner);
    }
  }

  void _showAdminBannerDialog(Map<String, dynamic> banner) {
    final titel     = banner['name']     as String? ?? '';
    final nachricht = banner['nachricht'] as String? ?? '';
    final style     = banner['style']    as String? ?? 'info';

    final Map<String, Color> bgColor = {
      'info':    const Color(0xFF1565C0),
      'warning': const Color(0xFFF57F17),
      'success': const Color(0xFF2E7D32),
      'danger':  const Color(0xFFC62828),
    };
    final Map<String, IconData> icons = {
      'info':    Icons.info_outline,
      'warning': Icons.warning_amber_rounded,
      'success': Icons.check_circle_outline,
      'danger':  Icons.error_outline,
    };
    final color = bgColor[style] ?? const Color(0xFF1565C0);
    final icon  = icons[style]  ?? Icons.info_outline;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
        clipBehavior: Clip.hardEdge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withOpacity(0.80)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    titel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
              ]),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (nachricht.isNotEmpty)
                    Text(
                      nachricht,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(_),
                      child: const Text('Verstanden',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('AppLifecycleState.resumed: Re-checking push token & permissions');
      _syncFcmTokenOnStart();
    }
  }

  Future<void> _syncFcmTokenOnStart() async {
    // Kurze Verzögerung, damit die UI bereit ist
    await Future.delayed(const Duration(milliseconds: 600));

    // Fall 1: Nativer Mobile-Build (Android & iOS via FCM)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final token = await FirebaseService().requestPermissionAndSyncToken();
        debugPrint('Native Mobile FCM Token synced on start: $token');
        final notificationsEnabled = await NotificationService().areNotificationsEnabled();
        if (mounted) {
          setState(() {
            _pushPermission = notificationsEnabled ? 'granted' : 'denied';
          });
        }
      } catch (e) {
        debugPrint('FCM start sync error: $e');
        if (mounted) {
          setState(() {
            _pushPermission = 'denied';
          });
        }
      }
      return;
    }

    // Fall 2: Web / iOS PWA
    await _apiService.syncFcmToken(); // Silent in UI

    final webPush = WebPushService();
    final perm = webPush.getNotificationPermission();

    // Wenn Permission bereits erteilt -> Subscription leise im Hintergrund auffrischen
    if (perm == 'granted') {
      await webPush.initWebPush();
      if (mounted) {
        setState(() {
          _pushPermission = 'granted';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _pushPermission = perm;
      });
    }

    if (webPush.shouldShowIosTutorial) {
      final prefs = await SharedPreferences.getInstance();
      final showedTutorial = prefs.getBool('ios_push_tutorial_shown') ?? false;
      if (!showedTutorial) {
        await prefs.setBool('ios_push_tutorial_shown', true);
        if (mounted) {
          _showIosTutorialPopup();
        }
      }
    }
  }

  void _handlePushBannerAction() {
    PushSettingsSheet.show(
      context,
      onTokenSynced: () {
        _syncFcmTokenOnStart();
      },
    );
  }

  Future<void> _loadUpcomingBirthdays() async {
    try {
      final list = await _apiService.getUpcomingBirthdays();
      if (mounted) {
        setState(() {
          _upcomingBirthdays = list;
        });
      }
    } catch (e) {
      debugPrint('Error loading upcoming birthdays: $e');
    }
  }

  Widget _buildBirthdaysWidget() {
    if (_birthdaysDismissed || _upcomingBirthdays.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE67E22), Color(0xFFD35400)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 40, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Text('🎉 ', style: TextStyle(fontSize: 16)),
                    Text(
                      'Geburtstage dieser Woche',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._upcomingBirthdays.take(3).map((b) {
                  final name = b['name'] ?? '${b['firstName'] ?? ''} ${b['lastName'] ?? ''}'.trim();
                  final daysUntil = b['daysUntil'] as int? ?? 0;
                  final age = b['age'];
                  final whenText = daysUntil == 0
                      ? '🎂 Heute!'
                      : (daysUntil == 1 ? 'Morgen' : 'in $daysUntil Tagen');

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Row(
                      children: [
                        const Icon(Icons.cake, size: 14, color: Colors.white70),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$name${age != null ? " ($age)" : ""}',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: daysUntil == 0 ? Colors.white : Colors.white24,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            whenText,
                            style: TextStyle(
                              color: daysUntil == 0 ? const Color(0xFFD35400) : Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
              onPressed: () => setState(() => _birthdaysDismissed = true),
              tooltip: 'Ausblenden',
            ),
          ),
        ],
      ),
    );
  }

  void _showIosTutorialPopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.apple, size: 28),
            SizedBox(width: 8),
            Expanded(child: Text('Apple (iOS) Hinweis')),
          ],
        ),
        content: const Text(
            'Um Push-Benachrichtigungen für neue Schichten zu erhalten, musst du diese App zu deinem Home-Bildschirm hinzufügen.\n\n'
            'Tippe dazu im Safari-Browser unten auf das "Teilen"-Symbol (Viereck mit Pfeil nach oben) und wähle "Zum Home-Bildschirm".\n\n'
            'Starte die App danach vom Home-Bildschirm neu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  void _showSyncQueueSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: _syncQueue.getPendingItems(),
              builder: (context, snapshot) {
                final items = snapshot.data ?? [];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.75,
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Drag handle
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade400,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.cloud_sync_outlined,
                                color: Colors.amber.shade900,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Ausstehende Vorgänge (${items.length})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                    ),
                                  ),
                                  const Text(
                                    'Offline-Warteschlange',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_syncQueue.isSyncing)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 20, color: Colors.amber.shade900),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Diese Aktionen wurden ohne Internet erfasst und sicher gespeichert. '
                                  'Sie werden automatisch synchronisiert, sobald das Signal wiederhergestellt ist.',
                                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'Keine ausstehenden Übertragungen.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        else
                          Flexible(
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final item = items[i];
                                final type = item['type'] as String?;
                                final desc = item['description'] as String? ?? 'Vorgang';
                                final retries = (item['retryCount'] as int?) ?? 0;
                                final createdAt = item['createdAt'] as String?;
                                String dateText = '';
                                if (createdAt != null) {
                                  try {
                                    final dt = DateTime.parse(createdAt).toLocal();
                                    dateText = DateFormat('dd.MM. HH:mm').format(dt);
                                  } catch (_) {}
                                }

                                IconData itemIcon = Icons.access_time;
                                Color iconColor = Colors.blue;
                                if (type == 'wachbuch_note') {
                                  itemIcon = Icons.book_outlined;
                                  iconColor = Colors.indigo;
                                } else if (desc.toLowerCase().contains('check-in') || desc.toLowerCase().contains('beginn')) {
                                  itemIcon = Icons.login;
                                  iconColor = Colors.green;
                                } else if (desc.toLowerCase().contains('check-out') || desc.toLowerCase().contains('ende')) {
                                  itemIcon = Icons.logout;
                                  iconColor = Colors.orange;
                                }

                                return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: iconColor.withOpacity(0.12),
                                    child: Icon(itemIcon, size: 18, color: iconColor),
                                  ),
                                  title: Text(
                                    desc,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    '$dateText • $retries Versuche',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                  trailing: const Icon(Icons.schedule, size: 16, color: Colors.amber),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: items.isEmpty || _syncQueue.isSyncing
                                    ? null
                                    : () async {
                                        setSheetState(() {});
                                        await _syncQueue.processQueue();
                                        if (context.mounted) {
                                          setSheetState(() {});
                                          if (_syncQueue.pendingCount == 0) {
                                            Navigator.pop(ctx);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('✅ Alle Vorgänge erfolgreich synchronisiert!'),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          }
                                        }
                                      },
                                icon: const Icon(Icons.sync),
                                label: const Text('Jetzt synchronisieren'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Schließen'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Timer? _pollTimer;

  void _setupDeepLink() {
    // 1. Initial URL hash on app start (e.g. #Slots/view/:id)
    final initialSlotId = DeepLinkService().getInitialSlotId();
    if (initialSlotId != null && initialSlotId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToSlotDeepLink(initialSlotId);
      });
    }

    // 2. Runtime hash changes & Web Push notification clicks
    DeepLinkService().onSlotDeepLink((slotId) {
      if (mounted && slotId.isNotEmpty) {
        _navigateToSlotDeepLink(slotId);
      }
    });
  }

  void _navigateToSlotDeepLink(String slotId) {
    DeepLinkService().clearDeepLink();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SlotsScreen(highlightId: slotId)),
    );
  }

  void _startUnreadNotificationPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        _fetchUnread();
      }
    });
  }

  void _onSyncQueueChanged() {
    if (mounted) {
      setState(() {
        _pendingQueueCount = _syncQueue.pendingCount;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncQueue.removeListener(_onSyncQueueChanged);
    _pollTimer?.cancel();
    _syncQueue.stopPeriodicSync();
    _calendarController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalCheckins() async {
    final prefs = await SharedPreferences.getInstance();
    final checkedInList = prefs.getStringList('admin_checked_slots') ?? [];
    final checkedOutList = prefs.getStringList('admin_checked_out_slots') ?? [];
    final inTimesJson = prefs.getString('admin_checked_times');
    final outTimesJson = prefs.getString('admin_checked_out_times');
    if (mounted) {
      setState(() {
        _checkedSlotIds = checkedInList.toSet();
        _checkedSlotOutIds = checkedOutList.toSet();
        try {
          if (inTimesJson != null && inTimesJson.trim().isNotEmpty) {
            _checkedSlotTimes = Map<String, String>.from(json.decode(inTimesJson));
          }
        } catch (e) {
          debugPrint('Dashboard: Error parsing admin_checked_times: $e');
        }
        try {
          if (outTimesJson != null && outTimesJson.trim().isNotEmpty) {
            _checkedSlotOutTimes = Map<String, String>.from(json.decode(outTimesJson));
          }
        } catch (e) {
          debugPrint('Dashboard: Error parsing admin_checked_out_times: $e');
        }
      });
    }
  }

  Future<void> _checkServerStatus() async {
    final status = await _apiService.pingServer();
    if (mounted) setState(() => _serverOnline = status);
  }

  void _refreshEvents() {
    setState(() {
      _eventsFuture = _fetchEvents();
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _persistFilters = prefs.getBool('persist_filters') ?? false;
        if (_persistFilters) {
          _showSlots = prefs.getBool('show_slots') ?? true;
          _showUrlaub = prefs.getBool('show_urlaub') ?? true;
          _showKrank = prefs.getBool('show_krank') ?? true;
          _showAbwesenheit = prefs.getBool('show_abwesenheit') ?? true;
          _showMeetings = prefs.getBool('show_meetings') ?? true;
        } else {
          _showSlots = true;
          _showUrlaub = true;
          _showKrank = true;
          _showAbwesenheit = true;
          _showMeetings = true;
        }
      });
    }
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('persist_filters', _persistFilters);
    if (_persistFilters) {
      await prefs.setBool('show_slots', _showSlots);
      await prefs.setBool('show_urlaub', _showUrlaub);
      await prefs.setBool('show_krank', _showKrank);
      await prefs.setBool('show_abwesenheit', _showAbwesenheit);
      await prefs.setBool('show_meetings', _showMeetings);
    }
  }

  Future<void> _fetchUnread() async {
    final count = await _apiService.getUnreadNotificationCount();
    final chatCount = await _apiService.getChatUnreadCount();
    if (mounted) {
      setState(() {
        _unreadCount = count;
        _chatUnreadCount = chatCount;
      });
    }
  }

  Future<void> _loadUser() async {
    try {
      await _aclService.init();
      final aName = await _storage.getAngestellteName();
      final uName = await _storage.getUsername();
      final name = aName ?? uName ?? 'Unbekannt';
      var aId = await _storage.getAngestellteId();
      final token = await _storage.getToken();

      // If angestellteId is missing, attempt auto-resolution
      if (aId == null || aId.isEmpty) {
        try {
          await _apiService.resolveCurrentUserAngestellte();
          aId = await _storage.getAngestellteId();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _username = name;
          _angestellteId = aId;
          _authToken = token;
        });
      }

      if (aId != null && aId.isNotEmpty) {
        final data = await _apiService.getAngestellteById(aId);
        if (mounted && data != null) {
          setState(() {
            _angestellte = data;
          });
        }
      }
    } catch (e) {
      debugPrint('Dashboard: _loadUser error: $e');
    }
  }

  Future<List<ScheduledEvent>> _fetchEvents() async {
    final List<ScheduledEvent> events = [];
    final DateFormat format = DateFormat('yyyy-MM-dd HH:mm:ss');

    try {
      final results = await Future.wait([
        _apiService.getSlots().catchError((_) => <Slot>[]),
        _apiService.getUrlaubs().catchError((_) => <Urlaub>[]),
        _apiService.getKrankentage().catchError((_) => <Krankentage>[]),
        _apiService.getAbwesenheiten().catchError((_) => <Abwesenheit>[]),
        _apiService.getMeetings().catchError((_) => <Meeting>[]),
        _apiService.getBereitschaften().catchError((_) => <Bereitschaft>[]),
      ]).timeout(const Duration(seconds: 15));

      final allSlots = (results[0] is List) ? (results[0] as List).whereType<Slot>().toList() : <Slot>[];
      final allUrlaubs = (results[1] is List) ? (results[1] as List).whereType<Urlaub>().toList() : <Urlaub>[];
      final allKrankentage = (results[2] is List) ? (results[2] as List).whereType<Krankentage>().toList() : <Krankentage>[];
      final allAbwesenheiten = (results[3] is List) ? (results[3] as List).whereType<Abwesenheit>().toList() : <Abwesenheit>[];
      final allMeetings = (results[4] is List) ? (results[4] as List).whereType<Meeting>().toList() : <Meeting>[];
      final allBereitschaften = (results[5] is List) ? (results[5] as List).whereType<Bereitschaft>().toList() : <Bereitschaft>[];

      _countSlots = allSlots.length;
      _countUrlaub = allUrlaubs.length;
      _countKrank = allKrankentage.length;
      _countAbwesenheit = allAbwesenheiten.length;
      _countMeetings = allMeetings.length;
      _rawSlots = allSlots;

      final slots = _showSlots ? allSlots : [];
      final urlaubs = _showUrlaub ? allUrlaubs : [];
      final kranks = _showKrank ? allKrankentage : [];
      final absences = _showAbwesenheit ? allAbwesenheiten : [];
      final meetings = _showMeetings ? allMeetings : [];
      // Bereitschaften immer anzeigen (kein Toggle)
      final bereitschaften = allBereitschaften;

    for (var slot in slots) {
      if (slot.dateStart != null && slot.dateEnd != null) {
        try {
          // Slots: dateStart/dateEnd sind UTC → in Lokalzeit konvertieren
          final start = format.parseUtc(slot.dateStart!).toLocal();
          final end = format.parseUtc(slot.dateEnd!).toLocal();

          // Parse slot color: direkte Schichtfarbe hat Priorität, dann Firmenfarbcode
          Color slotColor = Colors.blue.shade700;
          final colorHex = (slot.color?.isNotEmpty == true) ? slot.color : slot.firmaFarbcode;
          if (colorHex != null && colorHex.isNotEmpty) {
            try {
              slotColor = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
            } catch (_) {}
          }
          String subtitle = slot.objekteName ?? slot.positionsname ?? '';
          if (slot.kooperationspartnerName != null && slot.kooperationspartnerName!.isNotEmpty) {
            subtitle += (subtitle.isNotEmpty ? ' | ' : '') + 'Partner: ${slot.kooperationspartnerName}';
          }
          if (slot.checkin != null && slot.checkin!.isNotEmpty) {
            _checkedSlotIds.add(slot.id);
            final localIn = formatUtcToLocalTime(slot.checkin);
            if (localIn != null) {
              _checkedSlotTimes[slot.id] = localIn;
            }
          }
          if (slot.checkout != null && slot.checkout!.isNotEmpty) {
            _checkedSlotOutIds.add(slot.id);
            final localOut = formatUtcToLocalTime(slot.checkout);
            if (localOut != null) {
              _checkedSlotOutTimes[slot.id] = localOut;
            }
          }
          events.add(ScheduledEvent(
            slot.name.isNotEmpty ? slot.name : 'Schicht',
            subtitle: subtitle,
            from: start,
            to: end,
            background: slotColor,
            originalObject: slot,
          ));
        } catch (_) {}
      }
    }

    for (var urlaub in urlaubs) {
      if (urlaub.dateStart != null && urlaub.dateEnd != null) {
        try {
          // Urlaub: dateStart/dateEnd UTC → Lokalzeit für korrektes Tagesdatum
          final start = format.parseUtc(urlaub.dateStart!).toLocal();
          DateTime end = format.parseUtc(urlaub.dateEnd!).toLocal();
          // Normalize to midnight for all-day comparison
          final startDay = DateTime(start.year, start.month, start.day);
          DateTime endDay = DateTime(end.year, end.month, end.day);
          
          // Subtract 1 day for Espo's exclusive boundary vs SfCalendar's inclusive approach
          if (endDay.isAfter(startDay)) {
            endDay = endDay.subtract(const Duration(days: 1));
          }

          events.add(ScheduledEvent(
            urlaub.name.isNotEmpty ? urlaub.name : 'Urlaub',
            from: startDay,
            to: endDay,
            isAllDay: true,
            background: const Color(0xFFaa20bf),
            originalObject: urlaub,
          ));
        } catch (_) {}
      }
    }

    for (var krank in kranks) {
      if (krank.dateStart != null && krank.dateEnd != null) {
        try {
          final start = format.parseUtc(krank.dateStart!).toLocal();
          DateTime end = format.parseUtc(krank.dateEnd!).toLocal();
          final startDay = DateTime(start.year, start.month, start.day);
          DateTime endDay = DateTime(end.year, end.month, end.day);
          
          // Subtract 1 day for inclusive vs exclusive boundary
          if (endDay.isAfter(startDay)) {
            endDay = endDay.subtract(const Duration(days: 1));
          }

          events.add(ScheduledEvent(
            krank.name.isNotEmpty ? krank.name : 'Krank',
            from: startDay,
            to: endDay,
            isAllDay: true,
            background: const Color(0xFFeb0bb9),
            originalObject: krank,
          ));
        } catch (_) {}
      }
    }

    // Bereitschaften – immer sichtbar, orange Farbe
    for (var b in bereitschaften) {
      if (b.dateStart != null && b.dateEnd != null) {
        try {
          final startLocal = format.parseUtc(b.dateStart!).toLocal();
          final endLocal = format.parseUtc(b.dateEnd!).toLocal();
          final startDay = DateTime(startLocal.year, startLocal.month, startLocal.day);
          DateTime endDay = DateTime(endLocal.year, endLocal.month, endLocal.day);

          // EspoCRM: dateEnd ist exklusiv → für SfCalendar 1 Tag zurück
          if (endDay.isAfter(startDay)) {
            endDay = endDay.subtract(const Duration(days: 1));
          }

          events.add(ScheduledEvent(
            b.name.isNotEmpty ? b.name : 'Bereitschaft',
            from: startDay,
            to: endDay,
            isAllDay: true,
            background: const Color(0xFFFF8C00), // orange
            originalObject: b,
          ));
        } catch (_) {}
      }
    }

    for (var abs in absences) {
      if (abs.dateStart != null && abs.dateEnd != null) {
        try {
          // Use the explicit flag if present, otherwise fallback to check
          bool isAllDay = abs.isAllDay;
          if (!isAllDay && !abs.dateStart!.contains(':')) {
            isAllDay = true;
          }

          if (isAllDay) {
            final start = format.parseUtc(abs.dateStart!).toLocal();
            DateTime end = format.parseUtc(abs.dateEnd!).toLocal();
            final startDay = DateTime(start.year, start.month, start.day);
            DateTime endDay = DateTime(end.year, end.month, end.day);
            
            // Subtract 1 day for inclusive vs exclusive boundary
            if (endDay.isAfter(startDay)) {
              endDay = endDay.subtract(const Duration(days: 1));
            }
            
            events.add(ScheduledEvent(
              abs.name.isNotEmpty ? abs.name : 'Abwesenheit',
              from: startDay,
              to: endDay,
              isAllDay: true,
              background: const Color(0xFFFF0000),
              originalObject: abs,
            ));
          } else {
            // Specific time window – UTC → Lokalzeit
            final start = format.parseUtc(abs.dateStart!).toLocal();
            final end = format.parseUtc(abs.dateEnd!).toLocal();

            events.add(ScheduledEvent(
              abs.name.isNotEmpty ? abs.name : 'Abwesenheit',
              from: start,
              to: end,
              isAllDay: false,
              background: const Color(0xFFFF0000),
              originalObject: abs,
            ));
          }
        } catch (_) {}
      }
    }

    for (var m in meetings) {
      if (m.dateStart != null && m.dateEnd != null) {
        try {
          // Check if it's an "All Day" style meeting (starting at midnight UTC)
          bool isAllDay = m.dateStart!.contains('00:00:00') && m.dateEnd!.contains('00:00:00');
          
          DateTime start;
          DateTime end;

          if (isAllDay) {
            // All-day uses inclusive parsing for SfCalendar – UTC → Lokalzeit
            final startLocal = format.parseUtc(m.dateStart!).toLocal();
            final endLocal = format.parseUtc(m.dateEnd!).toLocal();
            start = DateTime(startLocal.year, startLocal.month, startLocal.day);
            DateTime endDay = DateTime(endLocal.year, endLocal.month, endLocal.day);
            
            // Subtract 1 day for Espo's exclusive boundary vs SfCalendar's inclusive approach
            if (endDay.isAfter(start)) {
              endDay = endDay.subtract(const Duration(days: 1));
            }
            end = endDay;
          } else {
            // Specific time window – UTC → Lokalzeit
            start = format.parseUtc(m.dateStart!).toLocal();
            end = format.parseUtc(m.dateEnd!).toLocal();
          }

          events.add(ScheduledEvent(
            m.name,
            from: start,
            to: end,
            isAllDay: isAllDay,
            background: Colors.blue.shade400,
            originalObject: m,
          ));
        } catch (_) {}
      }
    }

    } catch (e) {
      debugPrint('Dashboard fetch error: $e');
    }

    return events;
  }

  void _showEventDetails(ScheduledEvent event) {
    final dynamic obj = event.originalObject;
    final DateFormat timeFormat = DateFormat('HH:mm');
    final DateFormat dateFormat = DateFormat('dd.MM.yyyy');

    // On-demand clothing loading for Slots
    String? kleidungInfo;
    bool kleidungLoaded = obj is! Slot;
    bool kleidungTriggered = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Async load clothing info for Slots (fire once)
          if (obj is Slot && !kleidungLoaded && !kleidungTriggered) {
            kleidungTriggered = true;
            _apiService.getSlotById(obj.id).then((fullSlot) {
              if (fullSlot != null) {
                final nk = fullSlot.neueobjektkleidung;
                final nka = fullSlot.neueobjektkleidunganmerkung;
                setDialogState(() {
                  if (nk != null && nk.isNotEmpty && nk != 'null') {
                    kleidungInfo = nk.replaceAll(RegExp(r'[\[\]"]'), '').replaceAll(',', ', ');
                    if (nka != null && nka.isNotEmpty && nka != 'null') {
                      kleidungInfo = '$kleidungInfo\nAnmerkung: $nka';
                    }
                  } else if (nka != null && nka.isNotEmpty && nka != 'null') {
                    kleidungInfo = nka;
                  }
                  kleidungLoaded = true;
                });
              } else {
                setDialogState(() => kleidungLoaded = true);
              }
            }).catchError((_) {
              setDialogState(() => kleidungLoaded = true);
            });
          }

          return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.event_note, color: event.background),
            const SizedBox(width: 8),
            Expanded(child: Text(event.title, style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time/Date common part
            _buildDetailRow(Icons.calendar_today, 'Datum', dateFormat.format(event.from)),
            if (!event.isAllDay)
              _buildDetailRow(Icons.access_time, 'Zeit', '${timeFormat.format(event.from)} - ${timeFormat.format(event.to)}'),
            if (event.isAllDay && event.from.day != event.to.day)
              _buildDetailRow(Icons.date_range, 'Bis', dateFormat.format(event.to)),
            
            const Divider(height: 24),

            // Specific details based on object type
            if (obj is Slot) ...[
              if (AclService().isAppManager && obj.accountName != null) _buildDetailRow(Icons.business, 'Firma', obj.accountName!, colorCode: obj.firmaFarbcode),
              if (obj.objekteName != null) 
                _buildDetailRow(
                  Icons.location_on, 
                  'Objekt', 
                  obj.objekteName!,
                  onTap: () {
                    final addr = [
                      obj.neueobjektstrasse ?? obj.firmastrasse,
                      if (obj.neueobjektplz != null || obj.firmaplz != null) 
                        '${obj.neueobjektplz ?? obj.firmaplz} ${obj.neueobjektort ?? obj.firmaort}'
                      else 
                        (obj.neueobjektort ?? obj.firmaort)
                    ].where((s) => s != null && s.toString().isNotEmpty).join(', ');
                    _launchNavigation(addr);
                  },
                ),
              if (obj.positionsname != null) _buildDetailRow(Icons.work, 'Position', obj.positionsname!),
              if (kleidungInfo != null && kleidungInfo!.isNotEmpty) _buildDetailRow(Icons.checkroom, 'Arbeitskleidung', kleidungInfo!),
              if (!kleidungLoaded)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Kleidung wird geladen...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ]),
                ),
              if (obj.kooperationspartnerName != null) _buildDetailRow(Icons.handshake, 'Partner', obj.kooperationspartnerName!),
              
              // Check-In / Check-Out section
              const Divider(height: 24),
              Builder(builder: (_) {
                final isCheckedIn = _checkedSlotIds.contains(obj.id);
                final isCheckedOut = _checkedSlotOutIds.contains(obj.id);
                final checkInTime = _checkedSlotTimes[obj.id];
                final checkOutTime = _checkedSlotOutTimes[obj.id];
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isCheckedIn)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          const Icon(Icons.circle, color: Colors.green, size: 18),
                          const SizedBox(width: 4),
                          Text('Eingecheckt um $checkInTime', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green)),
                        ]),
                      ),
                    if (isCheckedOut)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          const Icon(Icons.circle, color: Colors.red, size: 18),
                          const SizedBox(width: 4),
                          Text('Ausgecheckt um $checkOutTime', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red)),
                        ]),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (!isCheckedIn)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                Navigator.pop(context);
                                await _calendarCheckIn(obj);
                              },
                              icon: const Icon(Icons.login, size: 18),
                              label: const Text('Einchecken'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            ),
                          ),
                        if (isCheckedIn && !isCheckedOut) ...[
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                Navigator.pop(context);
                                await _calendarCheckOut(obj);
                              },
                              icon: const Icon(Icons.logout, size: 18),
                              label: const Text('Auschecken'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                );
              }),
            ],

            if (obj is Urlaub) ...[
              _buildDetailRow(Icons.info_outline, 'Status', obj.status),
              if (obj.description != null && obj.description!.isNotEmpty) 
                _buildDetailRow(Icons.description, 'Beschreibung', obj.description!),
            ],

            if (obj is Krankentage) ...[
              _buildDetailRow(Icons.medical_services, 'Status', obj.status),
              if (obj.krankenscheinName != null) _buildDetailRow(Icons.file_present, 'Dokument', obj.krankenscheinName!),
            ],

            if (obj is Bereitschaft) ...[
              _buildDetailRow(Icons.shield_outlined, 'Typ', 'Bereitschaft'),
              _buildDetailRow(Icons.info_outline, 'Status', obj.status),
              if (obj.description != null && obj.description!.isNotEmpty)
                _buildDetailRow(Icons.description, 'Beschreibung', obj.description!),
            ],

            if (obj is Abwesenheit) ...[
              _buildDetailRow(Icons.timer_off, 'Typ', 'Termin / Abwesenheit'),
              if (obj.description != null && obj.description!.isNotEmpty) 
                _buildDetailRow(Icons.description, 'Notiz', obj.description!),
            ],

            if (obj is Meeting) ...[
              _buildDetailRow(Icons.info_outline, 'Status', obj.status),
              if (obj.parentName != null) _buildDetailRow(Icons.link, 'Bezug', obj.parentName!),
              if (obj.description != null && obj.description!.isNotEmpty) 
                _buildDetailRow(Icons.description, 'Beschreibung', obj.description!),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      );
        },
      ),
    );
  }

  Future<void> _calendarCheckIn(Slot slot) async {
    // Day check for workers
    if (!AclService().isAdmin && slot.dateStart != null) {
      try {
        final now = DateTime.now();
        final datePart = slot.dateStart!.split(' ')[0];
        final parts = datePart.split('-');
        if (parts.length >= 3) {
          final y = int.parse(parts[0]); final m = int.parse(parts[1]); final d = int.parse(parts[2]);
          if (now.year != y || now.month != m || now.day != d) {
            _showMsg('Check-In verweigert: Diese Schicht ist nicht für heute geplant.', Colors.red);
            return;
          }
        }
      } catch (_) {}
    }

    // GPS check via centralized LocationService
    final gpsResult = await LocationService().checkGeofence(slot);
    if (!gpsResult.isSuccess) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.location_off_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('Standort-Prüfung'),
              ],
            ),
            content: Text(gpsResult.message),
            actions: [
              if (gpsResult.targetLat != null || gpsResult.address != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    LocationService().openNavigation(
                      lat: gpsResult.targetLat,
                      lon: gpsResult.targetLon,
                      address: gpsResult.address,
                    );
                  },
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Route anzeigen'),
                ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);

    setState(() {
      _checkedSlotIds.add(slot.id);
      _checkedSlotTimes[slot.id] = timeStr;
    });

    // Persist locally (shared with SlotsScreen)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('admin_checked_slots', _checkedSlotIds.toList());
    await prefs.setString('admin_checked_times', json.encode(_checkedSlotTimes));

    // Sync to server
    _calendarSyncToServer(slot, checkInTime: timeStr);
  }

  Future<void> _calendarCheckOut(Slot slot) async {
    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);

    setState(() {
      _checkedSlotOutIds.add(slot.id);
      _checkedSlotOutTimes[slot.id] = timeStr;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('admin_checked_out_slots', _checkedSlotOutIds.toList());
    await prefs.setString('admin_checked_out_times', json.encode(_checkedSlotOutTimes));

    _calendarSyncToServer(slot, checkOutTime: timeStr);
  }

  Future<void> _calendarSyncToServer(Slot slot, {String? checkInTime, String? checkOutTime}) async {
    final Map<String, dynamic> data = {};

    if (checkInTime != null) {
      data['checkin'] = formatLocalToUtcDateTime(
        localHHmm: checkInTime,
        baseDateUtc: slot.dateStart,
      );
      if (slot.dateStart != null) {
        try {
          final startDt = espoUtcToLocal(slot.dateStart!);
          final parts = checkInTime.split(':');
          final checkDt = DateTime(startDt.year, startDt.month, startDt.day, int.parse(parts[0]), int.parse(parts[1]));
          
          final diff = startDt.difference(checkDt).inMinutes;

          if (checkDt.isAfter(startDt)) {
            data['checkinstat'] = '🔴'; // Zu spät
          } else if (diff <= 30) {
            data['checkinstat'] = '🟡'; // Knapp (innerhalb von 30 Min vorher)
          } else {
            data['checkinstat'] = '🟢'; // Rechtzeitig (mehr als 30 Min vorher)
          }
        } catch (_) {}
      }
    }
    if (checkOutTime != null) {
      data['checkout'] = formatLocalToUtcDateTime(
        localHHmm: checkOutTime,
        baseDateUtc: slot.dateEnd ?? slot.dateStart,
      );
    }

    if (data.isNotEmpty) {
      try {
        final success = await _apiService.patchSlot(slot.id, data);
        if (success && mounted) {
          _showMsg('✅ Daten an EspoCRM übertragen', Colors.green);
        }
      } catch (e) {
        final desc = checkInTime != null
          ? 'Check-In ${slot.angestellteName ?? slot.name} ($checkInTime)'
          : 'Check-Out ${slot.angestellteName ?? slot.name} ($checkOutTime)';
        await _syncQueue.enqueue(slotId: slot.id, data: data, description: desc);
        if (mounted) _showMsg('⏳ Kein Netz – Daten werden automatisch nachgesendet', Colors.orange.shade800);
      }
    }
  }

  Future<void> _launchNavigation(String? address) async {
    if (address == null || address.trim().isEmpty) return;
    await LocationService().openNavigation(address: address);
  }

  void _showMsg(String text, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: bg, duration: const Duration(seconds: 3)));
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Anzeigen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: Text('Schichten ($_countSlots)'),
                secondary: Icon(Icons.work, color: Colors.blue.shade700),
                value: _showSlots,
                onChanged: (val) {
                  setDialogState(() => _showSlots = val!);
                  setState(() {
                    _refreshEvents();
                    if (_persistFilters) _savePreferences();
                  });
                },
              ),
              CheckboxListTile(
                title: Text('Urlaub ($_countUrlaub)'),
                secondary: const Icon(Icons.beach_access, color: Color(0xFFaa20bf)),
                value: _showUrlaub,
                onChanged: (val) {
                  setDialogState(() => _showUrlaub = val!);
                  setState(() {
                    _refreshEvents();
                    if (_persistFilters) _savePreferences();
                  });
                },
              ),
              CheckboxListTile(
                title: Text('Krankentage ($_countKrank)'),
                secondary: const Icon(Icons.medical_services, color: Color(0xFFeb0bb9)),
                value: _showKrank,
                onChanged: (val) {
                  setDialogState(() => _showKrank = val!);
                  setState(() {
                    _refreshEvents();
                    if (_persistFilters) _savePreferences();
                  });
                },
              ),
              CheckboxListTile(
                title: Text('Abwesenheit ($_countAbwesenheit)'),
                secondary: const Icon(Icons.timer_off, color: Color(0xFFFF0000)),
                value: _showAbwesenheit,
                onChanged: (val) {
                  setDialogState(() => _showAbwesenheit = val!);
                  setState(() {
                    _refreshEvents();
                    if (_persistFilters) _savePreferences();
                  });
                },
              ),
              CheckboxListTile(
                title: Text('Meetings ($_countMeetings)'),
                secondary: Icon(Icons.calendar_month, color: Colors.blue.shade400),
                value: _showMeetings,
                onChanged: (val) {
                  setDialogState(() => _showMeetings = val!);
                  setState(() {
                    _refreshEvents();
                    if (_persistFilters) _savePreferences();
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _persistFilters = !_persistFilters;
                  _savePreferences();
                });
                setDialogState(() {});
              },
              child: Text(
                _persistFilters ? 'Merken aktiv' : 'Auswahl merken',
                style: TextStyle(
                  color: _persistFilters ? Colors.green.shade700 : null,
                  fontWeight: _persistFilters ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                setDialogState(() {
                  _showSlots = true;
                  _showUrlaub = true;
                  _showKrank = true;
                  _showAbwesenheit = true;
                  _showMeetings = true;
                });
                setState(() {
                  _refreshEvents();
                  if (_persistFilters) _savePreferences();
                });
              },
              child: const Text('Alle an'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fertig'),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildDetailRow(IconData icon, String label, String value, {String? colorCode, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text('$label: ', style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.bold)),
            Expanded(
              child: Row(
                children: [
                  if (colorCode != null) ...[
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Color(int.parse(colorCode.replaceFirst('#', '0xFF'))),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      value, 
                      style: TextStyle(
                        fontWeight: FontWeight.w500, 
                        fontSize: 13,
                        color: onTap != null ? Theme.of(context).primaryColor : null,
                        decoration: onTap != null ? TextDecoration.underline : null,
                      )
                    )
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _logout() async {
    final storage = SecureStorageService();
    await storage.deleteAll();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap, {Widget? trailing}) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
      trailing: trailing,
      onTap: () {
        Navigator.pop(context); // close drawer
        onTap();
      },
    );
  }

  // ─── DASHBOARD REDESIGN: HELPER & WIDGET METHODS ───

  bool _isMySlot(Slot slot) {
    if (_angestellteId != null && _angestellteId!.isNotEmpty) {
      if (slot.angestellteId == _angestellteId) return true;
    }
    if (_angestellte?.name.isNotEmpty == true && slot.angestellteName == _angestellte!.name) {
      return true;
    }
    if (_username.isNotEmpty && slot.angestellteName == _username) {
      return true;
    }
    return false;
  }

  List<Slot> _getUpcomingSlots() {
    final now = DateTime.now();
    final DateFormat format = DateFormat('yyyy-MM-dd HH:mm:ss');

    final filtered = _rawSlots.where((slot) {
      if (!_isMySlot(slot)) return false;
      if (slot.status == 'Storniert' || slot.status == 'Abgesagt' || slot.annahmeStatus == 'Abgelehnt') {
        return false;
      }
      if (slot.dateEnd == null) return false;
      try {
        final end = format.parseUtc(slot.dateEnd!).toLocal();
        return end.isAfter(now);
      } catch (_) {
        return false;
      }
    }).toList();

    filtered.sort((a, b) {
      try {
        final aStart = format.parseUtc(a.dateStart!).toLocal();
        final bStart = format.parseUtc(b.dateStart!).toLocal();
        return aStart.compareTo(bStart);
      } catch (_) {
        return 0;
      }
    });

    return filtered;
  }

  Map<String, double> _calculateMonthlyHours(DateTime month) {
    final DateFormat format = DateFormat('yyyy-MM-dd HH:mm:ss');
    final now = DateTime.now();

    double geleistet = 0.0;
    double geplant = 0.0;

    for (final slot in _rawSlots) {
      if (!_isMySlot(slot)) continue;
      if (slot.status == 'Storniert' || slot.status == 'Abgesagt' || slot.annahmeStatus == 'Abgelehnt') {
        continue;
      }
      if (slot.dateStart == null || slot.dateEnd == null) continue;

      try {
        final start = format.parseUtc(slot.dateStart!).toLocal();
        final end = format.parseUtc(slot.dateEnd!).toLocal();

        if (start.year != month.year || start.month != month.month) {
          continue;
        }

        double hours = 0.0;
        if (slot.stundenanzahl != null && slot.stundenanzahl! > 0) {
          hours = slot.stundenanzahl!;
        } else {
          hours = end.difference(start).inMinutes / 60.0;
        }

        final bool isGeleistet = (slot.checkout != null && slot.checkout!.isNotEmpty) ||
            slot.status == 'Durchgeführt' ||
            end.isBefore(now);

        if (isGeleistet) {
          geleistet += hours;
        } else {
          geplant += hours;
        }
      } catch (_) {}
    }

    return {
      'geleistet': geleistet,
      'geplant': geplant,
      'gesamt': geleistet + geplant,
    };
  }

  String _formatMonth(DateTime dt) {
    return '${_monthNames[dt.month - 1]} ${dt.year}';
  }

  String _formatHours(double hours) {
    return '${hours.toStringAsFixed(1).replaceAll('.', ',')} Std.';
  }

  Widget _buildProfileAvatarAction() {
    return GestureDetector(
      onTap: () {
        if (_angestellteId != null && _angestellteId!.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AngestellteProfileScreen(angestellteId: _angestellteId!)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kein Angestellten-Profil für diesen Benutzer hinterlegt.')),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(left: 6, right: 14),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white70, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6.5),
          child: (_angestellte?.rawData['mitarbeiterfotoId'] != null && _authToken != null)
              ? Image.network(
                  '${ServerConfig().apiUrl}/Attachment/file/${_angestellte?.rawData['mitarbeiterfotoId']}',
                  headers: _authToken!.startsWith('ApiKey ')
                      ? {'X-Api-Key': _authToken!.split(' ')[1]}
                      : {'Authorization': _authToken!},
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 22, color: Colors.white),
                )
              : const Icon(Icons.person, size: 22, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildViewSwitcher() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedTab == 0 ? Theme.of(context).primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: _selectedTab == 0
                      ? [
                          BoxShadow(
                            color: Theme.of(context).primaryColor.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.dashboard_rounded,
                      size: 16,
                      color: _selectedTab == 0 ? Colors.white : (isDark ? Colors.white60 : Colors.grey.shade600),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Dashboard',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _selectedTab == 0 ? Colors.white : (isDark ? Colors.white70 : Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedTab == 1 ? Theme.of(context).primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: _selectedTab == 1
                      ? [
                          BoxShadow(
                            color: Theme.of(context).primaryColor.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 16,
                      color: _selectedTab == 1 ? Colors.white : (isDark ? Colors.white60 : Colors.grey.shade600),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Kalender',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _selectedTab == 1 ? Colors.white : (isDark ? Colors.white70 : Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RefreshIndicator(
      onRefresh: () async {
        _refreshEvents();
        await _loadUser();
        await _fetchUnread();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            _buildKommendeDiensteCard(),
            _buildMonatsuebersichtCard(),
            _buildBrandingPill(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildKommendeDiensteCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final upcomingSlots = _getUpcomingSlots();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            'Kommende Dienste',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.grey.shade900,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (upcomingSlots.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28.0),
              child: Column(
                children: [
                  Icon(
                    Icons.event_available_rounded,
                    size: 44,
                    color: isDark ? Colors.white30 : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Keine anstehenden Dienste',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Aktuell sind keine kommenden Schichten eingeteilt.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                ...upcomingSlots.take(4).map((slot) => _buildUpcomingSlotItem(slot, isDark)),
                if (upcomingSlots.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InkWell(
                      onTap: () => setState(() => _selectedTab = 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_month, size: 14, color: Theme.of(context).primaryColor),
                            const SizedBox(width: 6),
                            Text(
                              'Alle ${upcomingSlots.length} kommenden Dienste im Kalender ansehen',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildUpcomingSlotItem(Slot slot, bool isDark) {
    final DateFormat format = DateFormat('yyyy-MM-dd HH:mm:ss');
    DateTime? start;
    DateTime? end;
    try {
      if (slot.dateStart != null) start = format.parseUtc(slot.dateStart!).toLocal();
      if (slot.dateEnd != null) end = format.parseUtc(slot.dateEnd!).toLocal();
    } catch (_) {}

    final now = DateTime.now();
    final bool isToday = start != null &&
        start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
    final bool isTomorrow = start != null &&
        start.year == now.year &&
        start.month == now.month &&
        start.day == now.day + 1;

    String dayOfWeek = '';
    String dayMonth = '';
    if (start != null) {
      dayOfWeek = isToday ? 'HEUTE' : (isTomorrow ? 'MORGEN' : _dayNames[start.weekday - 1].toUpperCase());
      dayMonth = '${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')}.';
    }

    final String timeStr = (start != null && end != null)
        ? '${DateFormat('HH:mm').format(start)} – ${DateFormat('HH:mm').format(end)} Uhr'
        : '';

    final double durationHours = (slot.stundenanzahl != null && slot.stundenanzahl! > 0)
        ? slot.stundenanzahl!
        : (start != null && end != null ? end.difference(start).inMinutes / 60.0 : 0.0);

    final String title = (slot.objekteName != null && slot.objekteName!.isNotEmpty)
        ? slot.objekteName!
        : (slot.name.isNotEmpty ? slot.name : 'Schicht');

    final String? position = slot.positionsname;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isToday
              ? const Color(0xFF10B981).withOpacity(0.5)
              : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
          width: isToday ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final subtitle = (slot.objekteName != null && slot.objekteName!.isNotEmpty)
                ? slot.objekteName!
                : (slot.positionsname ?? '');
            final event = ScheduledEvent(
              slot.name.isNotEmpty ? slot.name : 'Schicht',
              subtitle: subtitle,
              from: start ?? DateTime.now(),
              to: end ?? DateTime.now(),
              background: isToday ? const Color(0xFF10B981) : Theme.of(context).primaryColor,
              originalObject: slot,
            );
            _showEventDetails(event);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Date Badge Column
                Container(
                  width: 54,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isToday
                        ? const Color(0xFF10B981).withOpacity(0.15)
                        : (isDark ? Colors.white10 : Theme.of(context).primaryColor.withOpacity(0.08)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isToday
                          ? const Color(0xFF10B981)
                          : (isDark ? Colors.white24 : Theme.of(context).primaryColor.withOpacity(0.2)),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dayOfWeek,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isToday
                              ? const Color(0xFF10B981)
                              : (isDark ? Colors.white70 : Theme.of(context).primaryColor),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dayMonth,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Shift Info Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.grey.shade900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 12, color: isDark ? Colors.white54 : Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (durationHours > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '(${durationHours.toStringAsFixed(1).replaceAll('.', ',')}h)',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (position != null && position.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.shield_outlined, size: 12, color: Theme.of(context).primaryColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                position,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).primaryColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Action / Arrow Icon
                if (isToday)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SelfCheckinScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 1,
                    ),
                    child: const Text('Check-in', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  )
                else
                  Icon(Icons.chevron_right, size: 20, color: isDark ? Colors.white38 : Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonatsuebersichtCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hours = _calculateMonthlyHours(_selectedMonth);
    final geleistet = hours['geleistet'] ?? 0.0;
    final geplant = hours['geplant'] ?? 0.0;
    final gesamt = hours['gesamt'] ?? 0.0;

    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title & Month selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Monatsübersicht',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.grey.shade900,
                  letterSpacing: 0.2,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () {
                      setState(() {
                        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                      });
                    },
                  ),
                  Text(
                    _formatMonth(_selectedMonth),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () {
                      setState(() {
                        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          if (!isCurrentMonth)
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () => setState(() => _selectedMonth = DateTime.now()),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Zu aktuellem Monat',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).primaryColor,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 12),

          const SizedBox(height: 8),

          // Geleistete Stunden Row
          _buildHoursRow(
            label: 'Geleistete Stunden:',
            hours: geleistet,
            color: const Color(0xFF10B981),
            icon: Icons.check_circle_outline,
            isDark: isDark,
          ),

          const SizedBox(height: 14),

          // Geplante Stunden Row
          _buildHoursRow(
            label: 'Geplante Stunden:',
            hours: geplant,
            color: const Color(0xFFF59E0B),
            icon: Icons.schedule,
            isDark: isDark,
          ),

          const SizedBox(height: 14),

          Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1),

          const SizedBox(height: 14),

          // Gesamtstunden Row
          _buildHoursRow(
            label: 'Gesamtstunden:',
            hours: gesamt,
            color: Theme.of(context).primaryColor,
            icon: Icons.hourglass_full_rounded,
            isDark: isDark,
            isBold: true,
          ),

          // Progress bar if gesamt > 0
          if (gesamt > 0) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (geleistet / gesamt).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  geleistet >= gesamt ? const Color(0xFF10B981) : Theme.of(context).primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${((geleistet / gesamt) * 100).toInt()}% absolviert',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                InkWell(
                  onTap: () {
                    if (_angestellteId != null && _angestellteId!.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ArbeitszeitkontoScreen(),
                        ),
                      );
                    }
                  },
                  child: Text(
                    'Arbeitszeitkonto öffnen →',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHoursRow({
    required String label,
    required double hours,
    required Color color,
    required IconData icon,
    required bool isDark,
    bool isBold = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 16 : 15,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isDark ? (isBold ? Colors.white : Colors.white70) : (isBold ? Colors.black87 : Colors.grey.shade700),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(isDark ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _formatHours(hours),
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrandingPill(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 24),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222B) : Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Text(
        'app.secware.io',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white70 : Colors.black87,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Übersicht'),
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initialisierung...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: Image.asset(
                'assets/images/logo_cyan.png',
                width: 26,
                height: 26,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/images/logo.png',
                  width: 26,
                  height: 26,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(_selectedTab == 0 ? 'Dashboard' : 'Übersicht'),
            const SizedBox(width: 8),
            if (_serverOnline != null)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _serverOnline! ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_serverOnline! ? Colors.green : Colors.red).withOpacity(0.5),
                      blurRadius: 4,
                      spreadRadius: 1,
                    )
                  ],
                ),
              ),
          ],
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        actions: [
          if (_pendingQueueCount > 0)
            IconButton(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.cloud_upload_outlined, color: Colors.amberAccent),
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '$_pendingQueueCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              tooltip: '$_pendingQueueCount ausstehende Synchronisation(en)',
              onPressed: _showSyncQueueSheet,
            ),
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications),
                if (_unreadCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$_unreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
              _fetchUnread();
            },
            tooltip: 'Benachrichtigungen',
          ),
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat_bubble_outline_rounded),
                if (_chatUnreadCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '$_chatUnreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatListScreen()),
              );
              _fetchUnread();
            },
            tooltip: 'Chats',
          ),
          if (_selectedTab == 1) ...[
            IconButton(
              icon: const Icon(Icons.tune),
              onPressed: _showFilterDialog,
              tooltip: 'Filter',
            ),
            IconButton(
              icon: Icon(_calendarView == CalendarView.week ? Icons.calendar_month : Icons.view_week),
              onPressed: () {
                setState(() {
                  if (_calendarView == CalendarView.week) {
                    _calendarView = CalendarView.month;
                  } else {
                    _calendarView = CalendarView.week;
                  }
                  _calendarController.view = _calendarView;
                });
              },
              tooltip: 'Ansicht wechseln',
            ),
          ],
          _buildProfileAvatarAction(),
        ],
      ),
      drawer: Drawer(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 45, 16, 16),
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipOval(
                        child: Image.asset(
                          'assets/images/logo_cyan.png',
                          width: 28,
                          height: 28,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Image.asset(
                            'assets/images/logo.png',
                            width: 28,
                            height: 28,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'MB SECURITY',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _username,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (_angestellteId != null) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => AngestellteProfileScreen(angestellteId: _angestellteId!)));
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kein Angestellten-Profil für diesen Benutzer hinterlegt.')));
                          }
                        },
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 2),
                          ),
                          child: ClipOval(
                            child: (_angestellte?.rawData['mitarbeiterfotoId'] != null && _authToken != null)
                                ? Image.network(
                                    '${ServerConfig().apiUrl}/Attachment/file/${_angestellte?.rawData['mitarbeiterfotoId']}',
                                    headers: _authToken!.startsWith('ApiKey ') 
                                        ? {'X-Api-Key': _authToken!.split(' ')[1]} 
                                        : {'Authorization': _authToken!},
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 35, color: Colors.white),
                                  )
                                : const Icon(Icons.person, size: 35, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (_angestellte?.rawData['bewachungsregisterNummer'] != null && _angestellte!.rawData['bewachungsregisterNummer'].toString().isNotEmpty)
                                  ? 'BW-ID: ${_angestellte?.rawData['bewachungsregisterNummer']}'
                                  : 'Ausweis: ${_angestellte?.rawData['personalausweisnummer'] ?? "-"}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            if (_angestellte?.rawData['ePin'] != null && _angestellte!.rawData['ePin'].toString().isNotEmpty)
                              Text(
                                'E-Pin: ${_angestellte!.rawData['ePin']}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            Text(
                              'Firmen BW-ID: ${AppConstants.firmBewacherId}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            if (_angestellte?.personalnummer != null)
                              Text(
                                'Personal-Nr: ${_angestellte?.personalnummer}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildDrawerItem(Icons.dashboard, 'Dashboard', () {
                    // Drawer already pops in _buildDrawerItem, nothing else to do
                  }),
                  _buildDrawerItem(Icons.touch_app_rounded, 'Einstempeln / Check-In', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SelfCheckinScreen()));
                  }),
                  _buildDrawerItem(Icons.calendar_today, 'Schichten', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SlotsScreen()));
                  }),
                  _buildDrawerItem(Icons.access_time_filled, 'Arbeitszeitkonto', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ArbeitszeitkontoScreen()));
                  }),
                  _buildDrawerItem(Icons.flight_takeoff, 'Urlaub', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const UrlaubScreen()));
                  }),
                  _buildDrawerItem(Icons.local_hospital, 'Krankentage', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const KrankentageScreen()));
                  }),
                  _buildDrawerItem(Icons.timer_off, 'Abwesenheit', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AbwesenheitScreen()));
                  }),
                  _buildDrawerItem(Icons.book, 'Wachbuch', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const WachbuchListScreen()));
                  }),
                  _buildDrawerItem(Icons.calendar_month, 'Meetings', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MeetingListScreen()));
                  }),
                  if (_aclService.hasPermission('Document', 'read'))
                    _buildDrawerItem(Icons.folder, 'Dokumente', () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentListScreen()));
                    }),
                  _buildDrawerItem(Icons.people, 'Kollegen & Mitarbeiter', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AngestellteListScreen()));
                  }),
                  if (_aclService.hasPermission('Email', 'read'))
                    _buildDrawerItem(Icons.email, 'E-Mails', () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const EmailListScreen()));
                    }),
                  _buildDrawerItem(
                    Icons.chat_rounded,
                    'Chat',
                    () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListScreen()));
                      _fetchUnread();
                    },
                    trailing: _chatUnreadCount > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$_chatUnreadCount',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white30),
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                final colors = AppConstants.themes[themeProvider.selectedThemeName] ?? AppConstants.themes['Espo']!;
                return Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 16, top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Farbschema', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: AppConstants.themes.keys.map((themeName) {
                          final themeColors = AppConstants.themes[themeName]!;
                          final primary = themeColors['primary']!;
                          final isSelected = themeProvider.selectedThemeName == themeName;
                          return GestureDetector(
                            onTap: () => themeProvider.setColorTheme(themeName),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? Colors.white : Colors.white24,
                                  width: isSelected ? 3 : 1,
                                ),
                                boxShadow: isSelected ? [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))] : null,
                              ),
                              child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    SwitchListTile(
                      dense: true,
                      title: const Text('Dark Mode', style: TextStyle(color: Colors.white, fontSize: 14)),
                      activeColor: colors['secondary'],
                      value: themeProvider.themeMode == ThemeMode.dark,
                      onChanged: (value) {
                        themeProvider.setMode(value ? ThemeMode.dark : ThemeMode.light);
                      },
                      secondary: const Icon(Icons.dark_mode, color: Colors.white70),
                    ),
                  ],
                );
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.settings, color: Colors.white70, size: 22),
              title: const Text('Push-Einstellungen', style: TextStyle(color: Colors.white, fontSize: 14)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _pushPermission == 'granted' ? Colors.green.withOpacity(0.2) : Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _pushPermission == 'granted' ? 'Aktiv' : 'Einrichten',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _pushPermission == 'granted' ? Colors.greenAccent : Colors.amberAccent,
                  ),
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                PushSettingsSheet.show(context, onTokenSynced: _syncFcmTokenOnStart);
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.lock, color: Colors.white70, size: 22),
              title: const Text('Passwort ändern', style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context); // close drawer
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.logout, color: Colors.white70, size: 22),
              title: const Text('Abmelden', style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: _logout,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildBirthdaysWidget(),

          // ─── AKTIONEN: EINSTEMPELN & WACHBUCH (Prominent) ───
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SelfCheckinScreen()));
                    },
                    icon: const Icon(Icons.touch_app_rounded, size: 22),
                    label: const Text('Einstempeln', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Theme.of(context).primaryColor,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const WachbuchListScreen()));
                    },
                    icon: const Icon(Icons.book, size: 22),
                    label: const Text('Wachbuch', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.white54),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // ─── VIEW SWITCHER: [ 📊 Dashboard | 📅 Kalender ] ───
          _buildViewSwitcher(),

          // ─── HAUPTINHALT (Dashboard oder Kalender) ───
          Expanded(
            child: FutureBuilder<List<ScheduledEvent>>(
              future: _eventsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && _rawSlots.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError && _rawSlots.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cloud_off, size: 48, color: Colors.orange),
                          const SizedBox(height: 12),
                          const Text(
                            'Daten konnten nicht geladen werden',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${snapshot.error}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _refreshEvents,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Erneut versuchen'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final events = snapshot.data ?? [];

                return _selectedTab == 0
                    ? _buildDashboardView()
                    : _buildCalendarView(events);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarView(List<ScheduledEvent> events) {
    return Column(
      children: [
        if (!_showSlots && _countSlots > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: Colors.amber.shade900.withOpacity(0.92),
            child: Row(
              children: [
                const Icon(Icons.filter_alt_off, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Schichten-Filter ist deaktiviert ($_countSlots Schichten vorhanden)',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    setState(() {
                      _showSlots = true;
                      if (_persistFilters) _savePreferences();
                      _refreshEvents();
                    });
                  },
                  child: const Text('Einblenden', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),
        Expanded(
          child: SfCalendar(
            view: _calendarView,
            controller: _calendarController,
            dataSource: EventDataSource(events),
            firstDayOfWeek: 1,
            timeSlotViewSettings: const TimeSlotViewSettings(
              startHour: 5,
              endHour: 24,
              timeFormat: 'HH:mm',
              timeIntervalHeight: 60,
            ),
            monthViewSettings: const MonthViewSettings(
              appointmentDisplayMode: MonthAppointmentDisplayMode.appointment,
              appointmentDisplayCount: 3,
              monthCellStyle: MonthCellStyle(),
              showAgenda: true,
              agendaViewHeight: 160,
            ),
            onTap: (CalendarTapDetails details) {
              if (details.appointments != null && details.appointments!.isNotEmpty) {
                if (details.targetElement == CalendarElement.appointment) {
                  final ScheduledEvent event = details.appointments!.first as ScheduledEvent;
                  _showEventDetails(event);
                } else if (details.targetElement == CalendarElement.calendarCell) {
                  if (details.appointments!.length == 1) {
                    final ScheduledEvent event = details.appointments!.first as ScheduledEvent;
                    _showEventDetails(event);
                  }
                }
              }
            },
            appointmentBuilder: (context, calendarAppointmentDetails) {
              final ScheduledEvent event = calendarAppointmentDetails.appointments.first;
              final isMonthView = _calendarView == CalendarView.month;
              return Container(
                decoration: BoxDecoration(
                  color: event.background.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: isMonthView
                    ? Text(
                        event.title,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (event.subtitle != null)
                            Text(
                              event.subtitle!,
                              style: const TextStyle(color: Colors.white70, fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}
