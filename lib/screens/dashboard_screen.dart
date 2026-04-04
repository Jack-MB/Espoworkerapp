import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';
import '../services/sync_queue_service.dart';

import '../services/acl_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'slots_screen.dart';
import 'wachbuch_list_screen.dart';
import 'urlaub_screen.dart';
import 'krankentage_screen.dart';
import 'document_list_screen.dart';
import 'login_screen.dart';
import 'angestellte_list_screen.dart';
import 'angestellte_profile_screen.dart';
import 'notifications_screen.dart';
import 'abwesenheit_screen.dart';
import 'meeting_list_screen.dart';

import '../models/slot.dart';
import '../models/urlaub.dart';
import '../models/krankentage.dart';
import '../providers/theme_provider.dart';
import '../models/angestellte.dart';
import '../models/abwesenheit.dart';
import '../models/meeting.dart';
import 'package:provider/provider.dart';

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

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _apiService = ApiService();
  final AclService _aclService = AclService();
  final SecureStorageService _storage = SecureStorageService();
  CalendarView _calendarView = CalendarView.month;
  final CalendarController _calendarController = CalendarController();
  
  String _username = '';
  String? _angestellteId;
  int _unreadCount = 0;
  Angestellte? _angestellte;
  String? _authToken;

  Future<List<ScheduledEvent>> _eventsFuture = Future.value([]);
  List<ScheduledEvent> _allEvents = [];
  
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
  bool _isAdmin = false;
  bool _persistFilters = false;

  // Counts for filters
  int _countSlots = 0;
  int _countUrlaub = 0;
  int _countKrank = 0;
  int _countAbwesenheit = 0;
  int _countMeetings = 0;
  bool? _serverOnline;

  @override
  void initState() {
    super.initState();
    _refreshEvents();
    _loadUser();
    _fetchUnread();
    _loadPreferences();
    _checkServerStatus();
    _loadLocalCheckins();

    // Start sync queue for calendar check-ins
    _syncQueue.startPeriodicSync();
    _syncQueue.onSyncStateChanged = (count) {
      // In dashboard we don't have a badge yet, but we update status if needed
      debugPrint('Dashboard SyncQueue: $count items pending');
    };

    // FCM Token Sync beim Start
    _syncFcmTokenOnStart();
  }

  Future<void> _syncFcmTokenOnStart() async {
    // Kurze Verzögerung, damit die UI bereit ist
    await Future.delayed(const Duration(seconds: 2));
    final msg = await _apiService.syncFcmToken();
    if (mounted) {
       _showMsg('FCM Sync: $msg', msg.contains('OK') ? Colors.green : Colors.orange);
    }
  }

  @override
  void dispose() {
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
        if (inTimesJson != null) _checkedSlotTimes = Map<String, String>.from(json.decode(inTimesJson));
        if (outTimesJson != null) _checkedSlotOutTimes = Map<String, String>.from(json.decode(outTimesJson));
      });
    }
  }

  Future<void> _checkServerStatus() async {
    final status = await _apiService.pingServer();
    if (mounted) setState(() => _serverOnline = status);
  }

  void _refreshEvents() {
    setState(() {
      _eventsFuture = _fetchEvents().then((data) {
        _allEvents = data;
        return data;
      });
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
        }
      });
    }
    _refreshEvents();
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
    final notifs = await _apiService.getNotifications();
    if (mounted) {
      setState(() {
        _unreadCount = notifs.where((n) => !n.read).length;
      });
    }
  }

  void _loadUser() async {
    await _aclService.init();
    final aName = await _storage.getAngestellteName();
    final uName = await _storage.getUsername();
    final name = aName ?? uName ?? 'Unbekannt';
    final aId = await _storage.getAngestellteId();
    final token = await _storage.getToken();
    
    if (mounted) {
      setState(() {
        _username = name;
        _angestellteId = aId;
        _authToken = token;
      });
    }

    if (aId != null) {
      final data = await _apiService.getAngestellteById(aId);
      if (mounted && data != null) {
        setState(() {
          _angestellte = data;
        });
      }
    }

    final self = await _apiService.getSelfUser();
    if (mounted && self != null) {
      setState(() {
        _isAdmin = (self['user']?['isAdmin'] == true);
      });
      _refreshEvents();
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
      ]).timeout(const Duration(seconds: 15));

      final allSlots = (results[0] as List<Slot>?) ?? [];
      final allUrlaubs = (results[1] as List<Urlaub>?) ?? [];
      final allKrankentage = (results[2] as List<Krankentage>?) ?? [];
      final allAbwesenheiten = (results[3] as List<Abwesenheit>?) ?? [];
      final allMeetings = (results[4] as List<Meeting>?) ?? [];

      _countSlots = allSlots.length;
      _countUrlaub = allUrlaubs.length;
      _countKrank = allKrankentage.length;
      _countAbwesenheit = allAbwesenheiten.length;
      _countMeetings = allMeetings.length;

      final slots = _showSlots ? allSlots : [];
      final urlaubs = _showUrlaub ? allUrlaubs : [];
      final kranks = _showKrank ? allKrankentage : [];
      final absences = _showAbwesenheit ? allAbwesenheiten : [];
      final meetings = _showMeetings ? allMeetings : [];

    for (var slot in slots) {
      if (slot.dateStart != null && slot.dateEnd != null) {
        try {
          // Slots always have times, parse as UTC and convert to local
          final start = format.parse(slot.dateStart!);
          final end = format.parse(slot.dateEnd!);

          // Parse company color or fallback
          Color slotColor = Colors.blue.shade700;
          if (slot.firmaFarbcode != null && slot.firmaFarbcode!.isNotEmpty) {
            try {
              slotColor = Color(int.parse(slot.firmaFarbcode!.replaceFirst('#', '0xFF')));
            } catch (_) {}
          }
          String subtitle = slot.objekteName ?? slot.positionsname ?? '';
          if (slot.kooperationspartnerName != null && slot.kooperationspartnerName!.isNotEmpty) {
            subtitle += (subtitle.isNotEmpty ? ' | ' : '') + 'Partner: ${slot.kooperationspartnerName}';
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
          // Treat strings as literal dates to avoid timezone-induced day shifts
          final start = DateTime.parse(urlaub.dateStart!.substring(0, 10));
          DateTime end = DateTime.parse(urlaub.dateEnd!.substring(0, 10));
          
          // Subtract 1 day for Espo's exclusive boundary vs SfCalendar's inclusive approach
          if (urlaub.dateEnd!.contains('00:00:00') && urlaub.dateStart != urlaub.dateEnd) {
             if (end.isAfter(start)) {
               end = end.subtract(const Duration(days: 1));
             }
          }

          events.add(ScheduledEvent(
            urlaub.name.isNotEmpty ? urlaub.name : 'Urlaub',
            from: start,
            to: end,
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
          final start = DateTime.parse(krank.dateStart!.substring(0, 10));
          DateTime end = DateTime.parse(krank.dateEnd!.substring(0, 10));
          
          if (krank.dateEnd!.contains('00:00:00') && krank.dateStart != krank.dateEnd) {
             if (end.isAfter(start)) {
               end = end.subtract(const Duration(days: 1));
             }
          }

          events.add(ScheduledEvent(
            krank.name.isNotEmpty ? krank.name : 'Krank',
            from: start,
            to: end,
            isAllDay: true,
            background: const Color(0xFFeb0bb9),
            originalObject: krank,
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
            final start = DateTime.parse(abs.dateStart!.substring(0, 10));
            DateTime end = DateTime.parse(abs.dateEnd!.substring(0, 10));
            
            // Subtract 1 day for inclusive vs exclusive boundary
            if (abs.dateEnd!.contains('00:00:00')) {
                if (end.isAfter(start)) end = end.subtract(const Duration(days: 1));
            }
            
            events.add(ScheduledEvent(
              abs.name.isNotEmpty ? abs.name : 'Abwesenheit',
              from: start,
              to: end,
              isAllDay: true,
              background: const Color(0xFFFF0000),
              originalObject: abs,
            ));
          } else {
            // Specific time window
            final start = format.parse(abs.dateStart!);
            final end = format.parse(abs.dateEnd!);

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
            // All-day uses inclusive parsing for SfCalendar
            start = DateTime.parse(m.dateStart!.substring(0, 10));
            end = DateTime.parse(m.dateEnd!.substring(0, 10));
            
            // Subtract 1 day for Espo's exclusive boundary vs SfCalendar's inclusive approach
            if (end.isAfter(start)) {
              end = end.subtract(const Duration(days: 1));
            }
          } else {
            // Specific time window (converted to local)
            start = format.parse(m.dateStart!);
            end = format.parse(m.dateEnd!);
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
                final info = fullSlot.neueobjektkleidunganmerkung;
                setDialogState(() {
                  kleidungInfo = (info != null && info.isNotEmpty) ? info : null;
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
              if (AclService.isAdminApp && obj.accountName != null) _buildDetailRow(Icons.business, 'Firma', obj.accountName!, colorCode: obj.firmaFarbcode),
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
                          const Text('🟢 ', style: TextStyle(fontSize: 18)),
                          Text('Eingecheckt um $checkInTime', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green)),
                        ]),
                      ),
                    if (isCheckedOut)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          const Text('🔴 ', style: TextStyle(fontSize: 18)),
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

    // GPS check
    final gpsOk = await _checkGps(slot);
    if (!gpsOk) return;

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
    String? datePart;
    if (slot.dateStart != null && slot.dateStart!.contains(' ')) {
      datePart = slot.dateStart!.split(' ')[0];
    } else if (slot.dateStart != null) {
      datePart = slot.dateStart;
    }

    if (checkInTime != null) {
      data['checkin'] = datePart != null ? '$datePart $checkInTime:00' : null;
      if (slot.dateStart != null) {
        try {
          final startDt = DateFormat('yyyy-MM-dd HH:mm:ss').parse(slot.dateStart!);
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
      data['checkout'] = datePart != null ? '$datePart $checkOutTime:00' : null;
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

  Future<bool> _checkGps(Slot slot) async {
    try {
      if (slot.objekteId == null) {
        debugPrint('Kein Objekt verknüpft - überspringe GPS-Check');
        return true;
      }

      // GPS Koordinaten kommen laut User-Info immer über das Objekt
      final coords = await _apiService.getObjektCoordinates(slot.objekteId!);
      if (coords == null) {
        debugPrint('Keine Koordinaten im Objekt hinterlegt - überspringe GPS-Check');
        return true;
      }

      final double targetLat = coords['latk'] ?? 0;
      final double targetLon = coords['lonK'] ?? 0;
      final int allowedRadius = coords['rad'] ?? 30;

      if (targetLat == 0 || targetLon == 0) return true;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) { _showMsg('Bitte aktiviere GPS.', Colors.red); return false; }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) { _showMsg('Standort-Berechtigung verweigert.', Colors.red); return false; }
      }
      if (perm == LocationPermission.deniedForever) { _showMsg('GPS dauerhaft deaktiviert.', Colors.red); return false; }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 10));
      
      if (position.isMocked && !AclService().isAdmin) {
        _showMsg('Mock-Standort erkannt! Blockiert.', Colors.red);
        try { await _apiService.patchSlot(slot.id, {'mockStandort': true}); } catch (_) {}
        return false;
      }

      double dist = Geolocator.distanceBetween(position.latitude, position.longitude, targetLat, targetLon);
      if (dist > allowedRadius.toDouble()) {
        _showMsg('Zu weit vom Objekt entfernt (${dist.toStringAsFixed(0)}m / max ${allowedRadius}m).', Colors.red);
        return false;
      }
      return true;
    } catch (e) {
      _showMsg('GPS-Fehler: $e', Colors.red);
      return false;
    }
  }

  Future<void> _launchNavigation(String? address) async {
    if (address == null || address.trim().isEmpty) return;
    
    final query = Uri.encodeComponent(address.trim());
    final googleUrl = 'https://www.google.com/maps/search/?api=1&query=$query';
    final appleUrl = 'https://maps.apple.com/?q=$query';

    try {
      bool launched = await launchUrl(Uri.parse(googleUrl), mode: LaunchMode.externalApplication);
      if (!launched) {
        launched = await launchUrl(Uri.parse(appleUrl), mode: LaunchMode.externalApplication);
      }
      if (!launched) {
        _showMsg('Keine Navigations-App gefunden.', Colors.orange);
      }
    } catch (e) {
       debugPrint('Navigation launch error: $e');
       _showMsg('Keine Navigations-App gefunden.', Colors.orange);
    }
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

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
      onTap: () {
        Navigator.pop(context); // close drawer
        onTap();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Übersicht'),
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
        centerTitle: true,
        elevation: 0,
        actions: [
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
                                    '${AppConstants.apiUrl}/Attachment/file/${_angestellte?.rawData['mitarbeiterfotoId']}',
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
                  _buildDrawerItem(Icons.book, 'Wachbuch', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const WachbuchListScreen()));
                  }),
                  _buildDrawerItem(Icons.calendar_today, 'Schichten', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SlotsScreen()));
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
                  _buildDrawerItem(Icons.calendar_month, 'Meetings', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MeetingListScreen()));
                  }),
                  _buildDrawerItem(Icons.folder, 'Dokumente', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentListScreen()));
                  }),
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
          // ─── WACHBUCH BUTTON (Prominent) ───
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const WachbuchListScreen()));
              },
              icon: const Icon(Icons.book, size: 28),
              label: const Text('Wachbuch Öffnen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
              ),
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
                  return Center(child: Text('Fehler beim Laden des Kalenders: \${snapshot.error}'));
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
                      // If the user tapped on a specific appointment (either in month cell or agenda)
                      if (details.targetElement == CalendarElement.appointment) {
                        final ScheduledEvent event = details.appointments!.first as ScheduledEvent;
                        _showEventDetails(event);
                      } 
                      // If the user tapped on a day cell
                      else if (details.targetElement == CalendarElement.calendarCell) {
                        // Only open immediately if there is exactly one event
                        if (details.appointments!.length == 1) {
                          final ScheduledEvent event = details.appointments!.first as ScheduledEvent;
                          _showEventDetails(event);
                        }
                        // For multiple events, SfCalendar's 'showAgenda: true' will naturally 
                        // fill the bottom list, and the user can then tap an item there.
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
