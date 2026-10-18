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
import '../services/app_update_service.dart';
import 'dart:convert';
import 'self_checkin_screen.dart';
import '../services/checkin_state_service.dart';
import '../services/location_service.dart';
import 'slots_screen.dart';
import 'wachbuch_list_screen.dart';
import 'urlaub_screen.dart';
import 'krankentage_screen.dart';
import 'document_list_screen.dart';
import 'login_screen.dart';
import 'angestellte_profile_screen.dart';
import 'notifications_screen.dart';
import 'abwesenheit_screen.dart';
import 'abwesenheiten_hub_screen.dart';
import 'meeting_list_screen.dart';
import 'email_list_screen.dart';
import 'chat_list_screen.dart';
import 'arbeitszeitkonto_screen.dart';
import '../utils/espo_date.dart';
import 'change_password_screen.dart';
import 'settings_screen.dart';
import 'warehouse_hub_screen.dart';
import 'warehouse_scanner_screen.dart';

import '../models/slot.dart';
import '../models/urlaub.dart';
import '../models/krankentage.dart';
import '../providers/theme_provider.dart';
import '../models/angestellte.dart';
import '../models/abwesenheit.dart';
import '../models/meeting.dart';
import '../models/bereitschaft.dart';
import '../models/interne_taetigkeit.dart';
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
  Map<String, dynamic>? _activeAdminBanner;
  bool _bannerCollapsed = true;
  String _birthdayDisplayMode = 'all_week'; // 'all_week', 'one_day_before', 'disabled'
  DateTime? _birthdayDismissedUntil;

  Future<List<ScheduledEvent>> _eventsFuture = Future.value([]);
  
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
  bool _showInterneTaetigkeit = true;
  bool _persistFilters = false;

  // Counts for filters
  int _countSlots = 0;
  int _countUrlaub = 0;
  int _countKrank = 0;
  int _countAbwesenheit = 0;
  int _countMeetings = 0;
  int _countInterneTaetigkeit = 0;
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

    // Setup CheckinStateService for seamless synchronicity across all screens
    CheckinStateService().init();
    CheckinStateService().addListener(_onCheckinStateChanged);

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

    // OTA Update Check (asynchron nach erstem Frame)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService().checkAndPrompt(context, autoPrompt: true);
      }
    });
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

  void _loadDashboardData() {
    _refreshEvents();
    _fetchUnread();
    _loadLocalCheckins();
  }

  Future<void> _loadAdminBanner() async {
    final banner = await _apiService.getActiveBanner();
    if (mounted) {
      if (banner != null) {
        final bannerId = banner['id']?.toString() ?? '';
        bool isConfirmed = false;
        if (bannerId.isNotEmpty) {
          isConfirmed = await _apiService.isBannerConfirmed(bannerId);
        }
        banner['isConfirmed'] = isConfirmed;

        setState(() {
          _activeAdminBanner = banner;
          _bannerCollapsed = isConfirmed;
        });

        // Nur automatisch als Modal einblenden, wenn noch nicht vom Mitarbeiter bestätigt
        if (!isConfirmed) {
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) _showAdminBannerDialog(banner);
        }
      } else {
        setState(() {
          _activeAdminBanner = null;
        });
      }
    }
  }

  void _showAdminBannerDialog(Map<String, dynamic> banner) {
    final titel     = banner['name']     as String? ?? '';
    final nachricht = banner['nachricht'] as String? ?? '';
    final style     = banner['style']    as String? ?? 'info';
    final bannerId  = banner['id']?.toString() ?? '';
    final bool alreadyConfirmed = banner['isConfirmed'] == true;

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

    bool isAcknowledged = alreadyConfirmed;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.60),
      builder: (dialogContext) {
        final screenHeight = MediaQuery.of(dialogContext).size.height;
        final isDarkMode = Theme.of(dialogContext).brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              clipBehavior: Clip.hardEdge,
              elevation: 10,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: screenHeight * 0.85,
                  maxWidth: 580,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Header (Sticky)
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color, color.withValues(alpha: 0.85)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.20),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              titel.isNotEmpty ? titel : 'Wichtige Mitteilung',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                            tooltip: 'Schließen',
                            onPressed: () => Navigator.pop(dialogContext),
                          ),
                        ],
                      ),
                    ),

                    // 2. Scrollable Body
                    Flexible(
                      child: Scrollbar(
                        thumbVisibility: true,
                        thickness: 6,
                        radius: const Radius.circular(3),
                        child: SingleChildScrollView(
                          primary: true,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (nachricht.isNotEmpty)
                                _buildFormattedBannerContent(nachricht, isDarkMode),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 3. Footer (Sticky with Checkbox & Confirmation Button)
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      decoration: BoxDecoration(
                        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.grey.shade50,
                        border: Border(
                          top: BorderSide(
                            color: isDarkMode
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.grey.shade200,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (alreadyConfirmed)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.withOpacity(0.3)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Sie haben diese Mitteilung bereits verbindlich bestätigt.',
                                      style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: isSaving
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        isAcknowledged = !isAcknowledged;
                                      });
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: isAcknowledged,
                                      activeColor: color,
                                      onChanged: isSaving
                                          ? null
                                          : (val) {
                                              setDialogState(() {
                                                isAcknowledged = val ?? false;
                                              });
                                            },
                                    ),
                                    const Expanded(
                                      child: Text(
                                        'Ich habe diese Ankündigung aufmerksam gelesen und bestätige den Inhalt hiermit zur Kenntnis genommen zu haben.',
                                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (!alreadyConfirmed)
                                Expanded(
                                  flex: 1,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                                    child: const Text('Später', style: TextStyle(fontSize: 14)),
                                  ),
                                ),
                              if (!alreadyConfirmed) const SizedBox(width: 10),
                              Expanded(
                                flex: alreadyConfirmed ? 1 : 2,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: alreadyConfirmed
                                        ? Colors.grey.shade700
                                        : (isAcknowledged ? color : Colors.grey.shade400),
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: isSaving
                                      ? null
                                      : () async {
                                          if (alreadyConfirmed) {
                                            Navigator.pop(dialogContext);
                                            return;
                                          }
                                          if (!isAcknowledged) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Bitte setzen Sie den Haken zur Bestätigung.'),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                            return;
                                          }
                                          setDialogState(() => isSaving = true);
                                          final success = await _apiService.confirmBanner(bannerId);
                                          if (mounted) {
                                            if (success) {
                                              setState(() {
                                                _activeAdminBanner!['isConfirmed'] = true;
                                                _bannerCollapsed = true;
                                              });
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Bestätigung erfolgreich übermittelt. Vielen Dank!'),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            }
                                            Navigator.pop(dialogContext);
                                          }
                                        },
                                  child: isSaving
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : Text(
                                          alreadyConfirmed ? 'Schließen' : 'Verbindlich bestätigen',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFormattedBannerContent(String text, bool isDarkMode) {
    final textColor = isDarkMode ? Colors.white.withValues(alpha: 0.90) : const Color(0xFF2C3E50);
    final headingColor = isDarkMode ? Colors.white : const Color(0xFF1A252F);
    final boldColor = isDarkMode ? Colors.white : const Color(0xFF111827);

    final lines = text.split('\n');
    final widgets = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 10));
        continue;
      }

      // H1: # Title
      if (trimmed.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(
            trimmed.substring(2).trim(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: headingColor,
              letterSpacing: -0.3,
            ),
          ),
        ));
      }
      // H2/H3: ## or ### Subtitle
      else if (trimmed.startsWith('## ') || trimmed.startsWith('### ')) {
        final prefixLen = trimmed.startsWith('### ') ? 4 : 3;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            trimmed.substring(prefixLen).trim(),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: headingColor,
            ),
          ),
        ));
      }
      // Bullet list item: - ... or * ...
      else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        final content = trimmed.substring(2).trim();
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: headingColor)),
              Expanded(
                child: _buildRichTextSpan(content, textColor, boldColor),
              ),
            ],
          ),
        ));
      }
      // Regular paragraph or formatted line
      else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _buildRichTextSpan(trimmed, textColor, boldColor),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildRichTextSpan(String text, Color normalColor, Color boldColor) {
    final spans = <TextSpan>[];
    final parts = text.split('**');

    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      final isBold = i % 2 == 1;
      spans.add(TextSpan(
        text: parts[i],
        style: TextStyle(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: isBold ? boldColor : normalColor,
          fontSize: 14,
          height: 1.55,
        ),
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(fontSize: 14, height: 1.55, color: normalColor),
    );
  }

  Widget _buildActiveBannerCard(Map<String, dynamic> banner) {
    final bool isConfirmed = banner['isConfirmed'] == true;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final titel = banner['name'] as String? ?? 'Wichtige Mitteilung';
    final style = banner['style'] as String? ?? 'info';

    // ── EINKLAPPBARE SCHWEBENDE LEISTE (Bestätigt oder Manuell eingeklappt) ──
    if (_bannerCollapsed) {
      final bannerBg = isConfirmed
          ? (isDarkMode ? const Color(0xFF132A1C).withValues(alpha: 0.90) : const Color(0xFFE8F5E9))
          : (isDarkMode ? const Color(0xFF2D1810).withValues(alpha: 0.90) : const Color(0xFFFFF3E0));
      final bannerBorder = isConfirmed
          ? const Color(0xFF2E7D32).withValues(alpha: 0.35)
          : (style == 'danger' ? Colors.redAccent.withValues(alpha: 0.5) : const Color(0xFFE65100).withValues(alpha: 0.4));
      final textColor = isConfirmed
          ? (isDarkMode ? const Color(0xFFA5D6A7) : const Color(0xFF1B5E20))
          : (isDarkMode ? const Color(0xFFFFCC80) : const Color(0xFFE65100));

      return Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        decoration: BoxDecoration(
          color: bannerBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: bannerBorder, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _bannerCollapsed = false),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    isConfirmed ? Icons.check_circle_rounded : (style == 'danger' ? Icons.error_outline : Icons.warning_amber_rounded),
                    color: isConfirmed ? const Color(0xFF2E7D32) : (style == 'danger' ? Colors.redAccent : const Color(0xFFF57C00)),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isConfirmed ? 'Quittiert: $titel' : 'Mitteilung: $titel',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _showAdminBannerDialog(banner),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isConfirmed ? const Color(0xFF2E7D32) : const Color(0xFFE65100)).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isConfirmed ? 'Details' : 'Ansehen / Quittieren',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: textColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final Map<String, Color> bgColor = {
      'info': const Color(0xFF1565C0),
      'warning': const Color(0xFFF57F17),
      'success': const Color(0xFF2E7D32),
      'danger': const Color(0xFFC62828),
    };
    final Map<String, IconData> icons = {
      'info': Icons.info_outline,
      'warning': Icons.warning_amber_rounded,
      'success': Icons.check_circle_outline,
      'danger': Icons.error_outline,
    };
    final color = bgColor[style] ?? const Color(0xFF1565C0);
    final icon = icons[style] ?? Icons.info_outline;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showAdminBannerDialog(banner),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'AKTIVE ANKÜNDIGUNG',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: color,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        titel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isConfirmed
                        ? Colors.green.withOpacity(0.18)
                        : color,
                    borderRadius: BorderRadius.circular(8),
                    border: isConfirmed
                        ? Border.all(color: Colors.green.withOpacity(0.4))
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConfirmed ? Icons.check : Icons.assignment_turned_in_outlined,
                        color: isConfirmed ? Colors.green : Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isConfirmed ? 'Bestätigt' : 'Bestätigen',
                        style: TextStyle(
                          color: isConfirmed ? Colors.green : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => setState(() => _bannerCollapsed = true),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 20,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('birthday_display_mode') ?? 'all_week';
      final dismissedStr = prefs.getString('birthday_dismissed_until');
      DateTime? dismissedUntil;
      if (dismissedStr != null && dismissedStr.isNotEmpty) {
        dismissedUntil = DateTime.tryParse(dismissedStr);
      }

      if (mounted) {
        setState(() {
          _birthdayDisplayMode = mode;
          _birthdayDismissedUntil = dismissedUntil;
        });
      }

      // Falls dauerhaft deaktiviert oder bis nächsten Montag pausiert:
      if (mode == 'disabled') {
        if (mounted) setState(() => _upcomingBirthdays = []);
        return;
      }
      if (dismissedUntil != null && DateTime.now().isBefore(dismissedUntil)) {
        if (mounted) setState(() => _upcomingBirthdays = []);
        return;
      }

      final list = await _apiService.getUpcomingBirthdays();
      if (mounted) {
        setState(() {
          if (mode == 'one_day_before') {
            // Nur anzeigen, falls Geburtstag heute (0) oder morgen (1) ist
            _upcomingBirthdays = list.where((b) {
              final days = (b['daysUntil'] as int?) ?? 99;
              return days <= 1;
            }).toList();
          } else {
            _upcomingBirthdays = list;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading upcoming birthdays: $e');
    }
  }

  void _showBirthdayOptionsModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🎂 ', style: TextStyle(fontSize: 20)),
                    const Text(
                      'Geburtstags-Anzeige anpassen',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined, color: Color(0xFFE67E22)),
                  title: const Text('Erst 1 Tag vor dem Geburtstag anzeigen'),
                  subtitle: const Text('Erinnert dich nur heute oder am Vortag an Kollegen-Geburtstage'),
                  trailing: _birthdayDisplayMode == 'one_day_before' ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('birthday_display_mode', 'one_day_before');
                    await prefs.remove('birthday_dismissed_until');
                    _loadUpcomingBirthdays();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Eingestellt: Geburtstage werden erst 1 Tag vorher angezeigt.')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.snooze, color: Color(0xFFF59E0B)),
                  title: const Text('Diese Woche ausblenden'),
                  subtitle: const Text('Bis nächsten Montag nicht mehr auf dem Dashboard anzeigen'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final nextMonday = DateTime.now().add(Duration(days: 8 - DateTime.now().weekday));
                    final mondayStart = DateTime(nextMonday.year, nextMonday.month, nextMonday.day);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('birthday_dismissed_until', mondayStart.toIso8601String());
                    setState(() {
                      _birthdaysDismissed = true;
                      _birthdayDismissedUntil = mondayStart;
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Geburtstage für diese Woche ausgeblendet.')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined, color: Colors.redAccent),
                  title: const Text('Dauerhaft schließen / ausblenden'),
                  subtitle: const Text('Widget auf dem Dashboard dauerhaft deaktivieren'),
                  trailing: _birthdayDisplayMode == 'disabled' ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('birthday_display_mode', 'disabled');
                    setState(() {
                      _birthdaysDismissed = true;
                      _birthdayDisplayMode = 'disabled';
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Geburtstags-Widget dauerhaft ausgeblendet.')),
                      );
                    }
                  },
                ),
                if (_birthdayDisplayMode != 'all_week' || _birthdayDismissedUntil != null)
                  ListTile(
                    leading: const Icon(Icons.restore, color: Colors.blueAccent),
                    title: const Text('Zurücksetzen (Immer die ganze Woche anzeigen)'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('birthday_display_mode', 'all_week');
                      await prefs.remove('birthday_dismissed_until');
                      setState(() {
                        _birthdaysDismissed = false;
                        _birthdayDisplayMode = 'all_week';
                        _birthdayDismissedUntil = null;
                      });
                      _loadUpcomingBirthdays();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
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
                  children: [
                    const Text('🎉 ', style: TextStyle(fontSize: 16)),
                    Text(
                      _birthdayDisplayMode == 'one_day_before' ? 'Geburtstage heute & morgen' : 'Geburtstage dieser Woche',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
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
              onPressed: _showBirthdayOptionsModal,
              tooltip: 'Optionen / Schließen',
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
    CheckinStateService().removeListener(_onCheckinStateChanged);
    _syncQueue.removeListener(_onSyncQueueChanged);
    _pollTimer?.cancel();
    _syncQueue.stopPeriodicSync();
    _calendarController.dispose();
    super.dispose();
  }

  void _onCheckinStateChanged() {
    if (mounted) {
      setState(() {
        _checkedSlotIds = CheckinStateService().checkedInSlotIds.toSet();
        _checkedSlotOutIds = CheckinStateService().checkedOutSlotIds.toSet();
        _checkedSlotTimes = Map.from(CheckinStateService().checkedInTimes);
        _checkedSlotOutTimes = Map.from(CheckinStateService().checkedOutTimes);
      });
    }
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
          _showInterneTaetigkeit = prefs.getBool('show_interne_taetigkeit') ?? true;
        } else {
          _showSlots = true;
          _showUrlaub = true;
          _showKrank = true;
          _showAbwesenheit = true;
          _showMeetings = true;
          _showInterneTaetigkeit = true;
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
      await prefs.setBool('show_interne_taetigkeit', _showInterneTaetigkeit);
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
        _apiService.getInterneTaetigkeiten().catchError((_) => <InterneTaetigkeit>[]),
      ]).timeout(const Duration(seconds: 15));

      final allSlots = (results[0] is List) ? (results[0] as List).whereType<Slot>().toList() : <Slot>[];
      final allUrlaubs = (results[1] is List) ? (results[1] as List).whereType<Urlaub>().toList() : <Urlaub>[];
      final allKrankentage = (results[2] is List) ? (results[2] as List).whereType<Krankentage>().toList() : <Krankentage>[];
      final allAbwesenheiten = (results[3] is List) ? (results[3] as List).whereType<Abwesenheit>().toList() : <Abwesenheit>[];
      final allMeetings = (results[4] is List) ? (results[4] as List).whereType<Meeting>().toList() : <Meeting>[];
      final allBereitschaften = (results[5] is List) ? (results[5] as List).whereType<Bereitschaft>().toList() : <Bereitschaft>[];
      final allInterneTaetigkeiten = (results[6] is List) ? (results[6] as List).whereType<InterneTaetigkeit>().toList() : <InterneTaetigkeit>[];

      _countSlots = allSlots.length;
      _countUrlaub = allUrlaubs.length;
      _countKrank = allKrankentage.length;
      _countAbwesenheit = allAbwesenheiten.length;
      _countMeetings = allMeetings.length;
      _countInterneTaetigkeit = allInterneTaetigkeiten.length;

      final slots = _showSlots ? allSlots : [];
      final urlaubs = _showUrlaub ? allUrlaubs : [];
      final kranks = _showKrank ? allKrankentage : [];
      final absences = _showAbwesenheit ? allAbwesenheiten : [];
      final meetings = _showMeetings ? allMeetings : [];
      // Bereitschaften immer anzeigen (kein Toggle)
      final bereitschaften = allBereitschaften;
      final interneTaetigkeiten = _showInterneTaetigkeit ? allInterneTaetigkeiten : [];

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

    // Interne Tätigkeiten (Schule, Büroschichten, Fortbildung)
    for (var it in interneTaetigkeiten) {
      if (it.dateStart != null && it.dateEnd != null) {
        try {
          final startLocal = format.parseUtc(it.dateStart!).toLocal();
          final endLocal = format.parseUtc(it.dateEnd!).toLocal();

          Color bg;
          try {
            final hex = it.color.replaceAll('#', '');
            bg = Color(int.parse('FF$hex', radix: 16));
          } catch (_) {
            bg = it.typ == 'Schultag' ? const Color(0xFF0EA5E9) : const Color(0xFF6366F1);
          }

          final displayTitle = it.name.isNotEmpty ? it.name : it.typ;
          final displaySubtitle = '${it.typ} • ${it.stunden.toStringAsFixed(1)} Std.${it.ort != null && it.ort!.isNotEmpty ? ' • ${it.ort}' : ''}';

          if (it.isAllDay) {
            final startDay = DateTime(startLocal.year, startLocal.month, startLocal.day);
            DateTime endDay = DateTime(endLocal.year, endLocal.month, endLocal.day);
            if (endDay.isAfter(startDay)) {
              endDay = endDay.subtract(const Duration(days: 1));
            }
            events.add(ScheduledEvent(
              displayTitle,
              subtitle: displaySubtitle,
              from: startDay,
              to: endDay,
              isAllDay: true,
              background: bg,
              originalObject: it,
            ));
          } else {
            events.add(ScheduledEvent(
              displayTitle,
              subtitle: displaySubtitle,
              from: startLocal,
              to: endLocal,
              isAllDay: false,
              background: bg,
              originalObject: it,
            ));
          }
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
                    if (!CheckinStateService().isGloballyEnabled && !AclService().isAdmin) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Check-In ist derzeit systemweit deaktiviert.',
                                style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
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

            if (obj is InterneTaetigkeit) ...[
              _buildDetailRow(Icons.category_outlined, 'Tätigkeit', obj.typ),
              _buildDetailRow(Icons.info_outline, 'Status', obj.status),
              _buildDetailRow(Icons.access_time, 'Stunden', '${obj.stunden.toStringAsFixed(1)} Std.'),
              if (obj.pause > 0) _buildDetailRow(Icons.coffee_outlined, 'Pause', '${obj.pause} Min.'),
              if (obj.ort != null && obj.ort!.isNotEmpty)
                _buildDetailRow(Icons.location_on_outlined, 'Ort', obj.ort!),
              if (obj.beschreibung != null && obj.beschreibung!.isNotEmpty)
                _buildDetailRow(Icons.description_outlined, 'Notiz', obj.beschreibung!),
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
    if (!CheckinStateService().isGloballyEnabled && !AclService().isAdmin) {
      _showMsg('Check-In ist derzeit systemweit deaktiviert.', Colors.orange.shade800);
      return;
    }

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

    try {
      await CheckinStateService().performCheckIn(slot);
      if (mounted) _showMsg('✅ Erfolgreich eingecheckt', Colors.green);
    } catch (e) {
      if (e.toString().contains('deaktiviert') || e.toString().contains('Berechtigung')) {
        if (mounted) _showMsg('Fehler: $e', Colors.red);
        return;
      }
      debugPrint('Calendar checkin error, queueing: $e');
      final Map<String, dynamic> data = {
        'checkin': formatLocalToUtcDateTime(localHHmm: timeStr, baseDateUtc: slot.dateStart),
        'cI': '🟢',
      };
      final desc = 'Check-In ${slot.angestellteName ?? slot.name} ($timeStr)';
      await _syncQueue.enqueue(slotId: slot.id, data: data, description: desc);
      if (mounted) _showMsg('⏳ Kein Netz – Check-In wird automatisch nachgesendet', Colors.orange.shade800);
    }
  }

  Future<void> _calendarCheckOut(Slot slot) async {
    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);

    try {
      await CheckinStateService().performCheckOut(slot);
      if (mounted) _showMsg('✅ Erfolgreich ausgecheckt', Colors.green);
    } catch (e) {
      if (e.toString().contains('deaktiviert') || e.toString().contains('Berechtigung')) {
        if (mounted) _showMsg('Fehler: $e', Colors.red);
        return;
      }
      debugPrint('Calendar checkout error, queueing: $e');
      final Map<String, dynamic> data = {
        'checkout': formatLocalToUtcDateTime(localHHmm: timeStr, baseDateUtc: slot.dateEnd ?? slot.dateStart),
      };
      final desc = 'Check-Out ${slot.angestellteName ?? slot.name} ($timeStr)';
      await _syncQueue.enqueue(slotId: slot.id, data: data, description: desc);
      if (mounted) _showMsg('⏳ Kein Netz – Check-Out wird automatisch nachgesendet', Colors.orange.shade800);
    }
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
          final h = int.parse(parts[0]);
          final m = int.parse(parts[1]);
          var checkDt = DateTime(startDt.year, startDt.month, startDt.day, h, m);
          if (startDt.hour >= 16 && h < 12) {
            checkDt = checkDt.add(const Duration(days: 1));
          } else if (startDt.hour < 8 && h >= 18) {
            checkDt = checkDt.subtract(const Duration(days: 1));
          }
          final diff = checkDt.difference(startDt).inMinutes;

          String stat = '🟢';
          if (diff > 0) {
            stat = '🔴'; // Zu spät
          } else if (diff > -30) {
            stat = '🟡'; // Knapp (innerhalb von 30 Min vorher)
          } else {
            stat = '🟢'; // Rechtzeitig (mehr als 30 Min vorher)
          }
          data['cI'] = stat;
          data['checkinstat'] = stat;
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
        bool success = false;
        if (data.containsKey('checkin')) {
          success = await _apiService.checkInSlot(slot.id, checkInTime: data['checkin']);
        } else if (data.containsKey('checkout')) {
          success = await _apiService.checkOutSlot(slot.id, checkOutTime: data['checkout']);
        } else {
          success = await _apiService.patchSlot(slot.id, data);
        }
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
              CheckboxListTile(
                title: Text('Schule & Büro ($_countInterneTaetigkeit)'),
                secondary: const Icon(Icons.school_outlined, color: Color(0xFF0EA5E9)),
                value: _showInterneTaetigkeit,
                onChanged: (val) {
                  setDialogState(() => _showInterneTaetigkeit = val!);
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
                  _showInterneTaetigkeit = true;
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
    await ApiService().clearLocalCaches();
    await CheckinStateService().clearAll();
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
        titleSpacing: 0,
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
            const Text(
              'Übersicht',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 6),
            if (_serverOnline != null)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _serverOnline! ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_serverOnline! ? const Color(0xFF22C55E) : const Color(0xFFEF4444)).withOpacity(0.5),
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
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Optionen',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onSelected: (value) {
              if (value == 'view') {
                setState(() {
                  if (_calendarView == CalendarView.week) {
                    _calendarView = CalendarView.month;
                  } else {
                    _calendarView = CalendarView.week;
                  }
                  _calendarController.view = _calendarView;
                });
              } else if (value == 'filter') {
                _showFilterDialog();
              } else if (value == 'scan') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WarehouseScannerScreen()),
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'view',
                child: Row(
                  children: [
                    Icon(
                      _calendarView == CalendarView.week ? Icons.calendar_month : Icons.view_week,
                      color: Theme.of(context).primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(_calendarView == CalendarView.week ? 'Monatsansicht' : 'Wochenansicht'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'filter',
                child: Row(
                  children: [
                    Icon(Icons.tune, color: Theme.of(context).primaryColor, size: 20),
                    const SizedBox(width: 12),
                    const Text('Schichten filtern'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'scan',
                child: Row(
                  children: [
                    Icon(Icons.qr_code_scanner, color: Color(0xFFC084FC), size: 20),
                    SizedBox(width: 12),
                    Text('Material-QR scannen'),
                  ],
                ),
              ),
            ],
          ),
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
                  _buildDrawerItem(Icons.touch_app_rounded, 'Einstempeln / Check-In', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SelfCheckinScreen()));
                    _loadDashboardData();
                  }),
                  _buildDrawerItem(Icons.calendar_today, 'Schichten / Dienstplan', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SlotsScreen()));
                    _loadDashboardData();
                  }),
                  _buildDrawerItem(Icons.book, 'Wachbuch', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const WachbuchListScreen()));
                  }),
                  _buildDrawerItem(
                    Icons.inventory_2_rounded,
                    'Material & Kleidung (Depot)',
                    () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const WarehouseHubScreen()));
                    },
                  ),
                  _buildDrawerItem(
                    Icons.qr_code_scanner,
                    'QR-Scanner (Ausrüstung & Lager)',
                    () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const WarehouseScannerScreen()));
                    },
                  ),
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
                  if (_aclService.hasPermission('Document', 'read'))
                    _buildDrawerItem(Icons.folder, 'Dokumente', () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentListScreen()));
                    }),
                  if (_aclService.hasPermission('Email', 'read'))
                    _buildDrawerItem(Icons.email, 'E-Mails', () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const EmailListScreen()));
                    }),
                  _buildDrawerItem(Icons.calendar_month, 'Meetings', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MeetingListScreen()));
                  }),
                  const Divider(color: Colors.white24, height: 16),
                  _buildDrawerItem(Icons.access_time_filled, 'Arbeitszeitkonto', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ArbeitszeitkontoScreen()));
                  }),
                  _buildDrawerItem(Icons.flight_takeoff, 'Urlaub', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AbwesenheitenHubScreen(initialIndex: 0)));
                  }),
                  _buildDrawerItem(Icons.local_hospital, 'Krankentage', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AbwesenheitenHubScreen(initialIndex: 1)));
                  }),
                  _buildDrawerItem(Icons.timer_off, 'Termine & Abwesenheit', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AbwesenheitenHubScreen(initialIndex: 2)));
                  }),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 16),
            _buildDrawerItem(Icons.settings_outlined, 'Einstellungen', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            }),
            _buildDrawerItem(Icons.logout, 'Abmelden', _logout),
            const SizedBox(height: 16),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildBirthdaysWidget(),
          if (_activeAdminBanner != null)
            _buildActiveBannerCard(_activeAdminBanner!),

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
                    onPressed: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const SelfCheckinScreen()));
                      _loadDashboardData();
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
          
          // ─── KALENDER ───
          Expanded(
            child: FutureBuilder<List<ScheduledEvent>>(
              future: _eventsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cloud_off, size: 48, color: Colors.orange),
                          const SizedBox(height: 12),
                          const Text(
                            'Kalender konnte nicht geladen werden',
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

                return SfCalendar(
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
