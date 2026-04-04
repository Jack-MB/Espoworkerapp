import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/sync_queue_service.dart';
import '../models/slot.dart';
import '../core/constants.dart';
import '../services/acl_service.dart';

class SlotsScreen extends StatefulWidget {
  final String? highlightId;
  const SlotsScreen({Key? key, this.highlightId}) : super(key: key);

  @override
  _SlotsScreenState createState() => _SlotsScreenState();
}

class _SlotsScreenState extends State<SlotsScreen> {
  final ApiService _apiService = ApiService();
  final SyncQueueService _syncQueue = SyncQueueService();
  List<Slot> _allSlots = [];
  List<Slot> _filteredSlots = [];
  bool _isLoading = true;
  String? _defaultPresetName;
  int _pendingSyncCount = 0;

  // Filter state
  String? _selectedAngestellte;
  String? _selectedObjekt;
  String? _selectedAccount;
  DateTimeRange? _selectedDateRange;

  // Available filter options (built from data)
  List<String> _angestellteOptions = [];
  List<String> _objekteOptions = [];
  List<String> _accountOptions = [];

  // Local presence check state
  Set<String> _checkedSlotIds = {};
  Set<String> _checkedSlotOutIds = {};
  Map<String, String> _checkedSlotTimes = {}; // Store check-in times (e.g., "HH:mm")
  Map<String, String> _checkedSlotOutTimes = {}; // Store check-out times

  // Bulk state
  bool _isBulkMode = false;
  final Set<String> _bulkSelectedIds = {};
  List<Map<String, dynamic>> _presets = [];

  @override
  void initState() {
    super.initState();
    _initializeData();
    
    // Start the sync queue for retrying failed server syncs
    _syncQueue.onSyncStateChanged = (count) {
      if (mounted) setState(() => _pendingSyncCount = count);
    };
    _syncQueue.startPeriodicSync();
    _syncQueue.getPendingCount().then((c) {
      if (mounted) setState(() => _pendingSyncCount = c);
    });
    
    // Level 2: If we have a highlightId, we might need a custom date range to see it
    if (widget.highlightId != null) {
      _handleHighlightedSlot();
    }
  }

  @override
  void dispose() {
    _syncQueue.stopPeriodicSync();
    super.dispose();
  }

  Future<void> _handleHighlightedSlot() async {
    // If we have a highlight ID, fetch that specific slot to know its date
    final slot = await _apiService.getSlotById(widget.highlightId!);
    if (slot != null && slot.dateStart != null) {
      final date = DateTime.parse(slot.dateStart!);
      setState(() {
        _selectedDateRange = DateTimeRange(
          start: DateTime(date.year, date.month, date.day),
          end: DateTime(date.year, date.month, date.day),
        );
      });
      // Trigger a reload for this specific day
      await _loadSlots();
      // Show details
      _showSlotDetails(slot);
    }
  }

  Future<void> _initializeData() async {
    await AclService().init();
    await _loadPresets();
    await _loadCheckedSlots();
    Map<String, dynamic>? defaultPreset;
    if (_defaultPresetName != null) {
      for (var p in _presets) {
        if (p['name'] == _defaultPresetName) {
          defaultPreset = p;
          break;
        }
      }
    }

    if (defaultPreset != null) {
      _applyPreset(defaultPreset);
    } else {
      _loadSlots();
    }
  }

  Future<void> _loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final String? presetsJson = prefs.getString('slot_presets');
    if (presetsJson != null) {
      try {
        setState(() {
          _presets = List<Map<String, dynamic>>.from(json.decode(presetsJson));
        });
      } catch (e) {
        debugPrint('Error loading presets: $e');
      }
    }
    
    // Add default presets if empty
    if (_presets.isEmpty) {
      _presets.addAll([
        {
          'name': 'Heute',
          'relativeRange': 'today',
        },
        {
          'name': 'Aktueller Monat',
          'relativeRange': 'current_month',
        },
        {
          'name': 'Nächster Monat',
          'relativeRange': 'next_month',
        },
      ]);
    }
    
    _defaultPresetName = prefs.getString('slot_default_preset');
    setState(() {}); // Ensure UI updates with loaded presets and default
  }

  Future<void> _setDefaultPreset(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name == null) {
      await prefs.remove('slot_default_preset');
    } else {
      await prefs.setString('slot_default_preset', name);
    }
    setState(() {
      _defaultPresetName = name;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(name == null ? 'Standard-Filter entfernt' : 'Filter "$name" als Standard gesetzt.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveCurrentAsPreset(String name) async {
    final Map<String, dynamic> preset = {
      'name': name,
      'angestellte': _selectedAngestellte,
      'objekt': _selectedObjekt,
      'account': AclService.isAdminApp ? _selectedAccount : null,
    };
    
    // If a custom date range is selected, save it relative or absolute? 
    // Usually relative is better.
    if (_selectedDateRange != null) {
      preset['start'] = _selectedDateRange!.start.toIso8601String();
      preset['end'] = _selectedDateRange!.end.toIso8601String();
    }

    setState(() {
      _presets.add(preset);
    });
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('slot_presets', json.encode(_presets));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Filter "$name" gespeichert.')));
    }
  }

  void _applyPreset(Map<String, dynamic> preset) {
    setState(() {
      _selectedAngestellte = preset['angestellte'];
      _selectedObjekt = preset['objekt'];
      _selectedAccount = preset['account'];
      
      if (preset['relativeRange'] == 'today') {
        final now = DateTime.now();
        _selectedDateRange = DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day),
        );
      } else if (preset['relativeRange'] == 'current_month') {
        final now = DateTime.now();
        _selectedDateRange = DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0), // Last day of month
        );
      } else if (preset['relativeRange'] == 'next_month') {
        final now = DateTime.now();
        _selectedDateRange = DateTimeRange(
          start: DateTime(now.year, now.month + 1, 1),
          end: DateTime(now.year, now.month + 2, 0), // Last day of next month
        );
      } else if (preset['start'] != null) {
        _selectedDateRange = DateTimeRange(
          start: DateTime.parse(preset['start']),
          end: DateTime.parse(preset['end']),
        );
      }
    });
    _loadSlots(); // Refetch because date range might have changed
  }

  Future<void> _loadSlots() async {
    setState(() => _isLoading = true);
    // Respect the currently selected date range on refresh to prevent clearing custom fetches
    final slots = await _apiService.getSlots(
      startDate: _selectedDateRange?.start,
      endDate: _selectedDateRange?.end,
    );
    
    // Extract unique filter options
    final angestellteSet = <String>{};
    final objekteSet = <String>{};
    final accountSet = <String>{};

    for (var s in slots) {
      if (s.angestellteName != null && s.angestellteName!.isNotEmpty) {
        angestellteSet.add(s.angestellteName!);
      }
      if (s.objekteName != null && s.objekteName!.isNotEmpty) {
        objekteSet.add(s.objekteName!);
      }
      if (s.accountName != null && s.accountName!.isNotEmpty) {
        accountSet.add(s.accountName!);
      }
    }

    setState(() {
      _allSlots = slots;
      _angestellteOptions = angestellteSet.toList()..sort();
      _objekteOptions = objekteSet.toList()..sort();
      _accountOptions = accountSet.toList()..sort();
      _isLoading = false;
      
      // Sync local tracking with server data
      for (var slot in slots) {
        if (slot.checkin != null && slot.checkin!.isNotEmpty) {
          _checkedSlotIds.add(slot.id);
          if (slot.checkin!.contains(' ')) {
            _checkedSlotTimes[slot.id] = slot.checkin!.split(' ')[1].substring(0, 5);
          }
        }
        if (slot.checkout != null && slot.checkout!.isNotEmpty) {
          _checkedSlotOutIds.add(slot.id);
          if (slot.checkout!.contains(' ')) {
            _checkedSlotOutTimes[slot.id] = slot.checkout!.split(' ')[1].substring(0, 5);
          }
        }
      }
    });
    _applyFilters();
  }

  Future<void> _loadCheckedSlots() async {
    final prefs = await SharedPreferences.getInstance();
    final checkedInList = prefs.getStringList('admin_checked_slots') ?? [];
    final checkedOutList = prefs.getStringList('admin_checked_out_slots') ?? [];
    final inTimesJson = prefs.getString('admin_checked_times');
    final outTimesJson = prefs.getString('admin_checked_out_times');
    
    setState(() {
      _checkedSlotIds = checkedInList.toSet();
      _checkedSlotOutIds = checkedOutList.toSet();
      if (inTimesJson != null) {
        _checkedSlotTimes = Map<String, String>.from(json.decode(inTimesJson));
      }
      if (outTimesJson != null) {
        _checkedSlotOutTimes = Map<String, String>.from(json.decode(outTimesJson));
      }
    });
  }

  Future<void> _toggleSlotChecked(Slot slot, bool? value) async {
    if (value == true) {
      // PRE-CHECK: Prevent early/late check-in on the wrong day for workers
      if (!AclService().isAdmin && slot.dateStart != null) {
        try {
          final now = DateTime.now();
          final datePart = slot.dateStart!.split(' ')[0];
          final parts = datePart.split('-');
          if (parts.length >= 3) {
            final shiftYear = int.parse(parts[0]);
            final shiftMonth = int.parse(parts[1]);
            final shiftDay = int.parse(parts[2]);
            if (now.year != shiftYear || now.month != shiftMonth || now.day != shiftDay) {
              _showError('Check-In verweigert: Diese Schicht ist nicht für heute geplant.');
              return;
            }
          }
        } catch (e) {
          debugPrint('Date Validation Error: $e');
        }
      }

      // GPS Geofence Check
      final isValid = await _checkLocationAccess(slot);
      if (!isValid) return;
      _performCheckIn(slot);
    } else {
      _performCheckOut(slot);
    }
  }

  void _performCheckIn(Slot slot) {
    final id = slot.id;
    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);
    
    setState(() {
      _checkedSlotIds.add(id);
      if (!_checkedSlotTimes.containsKey(id)) {
        _checkedSlotTimes[id] = timeStr;
      }
    });

    _saveLocalPresence();
    _syncSlotToServer(slot, checkInTime: timeStr);
  }

  void _performCheckOut(Slot slot) {
    setState(() {
      _checkedSlotIds.remove(slot.id);
      _checkedSlotTimes.remove(slot.id);
    });
    _saveLocalPresence();
    _syncSlotToServer(slot, checkInTime: "");
  }

  Future<void> _saveLocalPresence() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('admin_checked_slots', _checkedSlotIds.toList());
    await prefs.setString('admin_checked_times', json.encode(_checkedSlotTimes));
  }

  Future<void> _toggleSlotOutChecked(Slot slot, bool? value) async {
    final id = slot.id;
    setState(() {
      if (value == true) {
        _checkedSlotOutIds.add(id);
        if (!_checkedSlotOutTimes.containsKey(id)) {
          _checkedSlotOutTimes[id] = DateFormat('HH:mm').format(DateTime.now());
        }
      } else {
        _checkedSlotOutIds.remove(id);
        _checkedSlotOutTimes.remove(id);
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('admin_checked_out_slots', _checkedSlotOutIds.toList());
    await prefs.setString('admin_checked_out_times', json.encode(_checkedSlotOutTimes));

    // Sync to Server
    _syncSlotToServer(slot, checkOutTime: value == true ? _checkedSlotOutTimes[id] : "");
  }

  Future<void> _updateCheckInTime(Slot slot, String time) async {
    setState(() {
      _checkedSlotTimes[slot.id] = time;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_checked_times', json.encode(_checkedSlotTimes));
    
    _syncSlotToServer(slot, checkInTime: time);
  }

  Future<void> _updateCheckOutTime(Slot slot, String time) async {
    setState(() {
      _checkedSlotOutTimes[slot.id] = time;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_checked_out_times', json.encode(_checkedSlotOutTimes));

    _syncSlotToServer(slot, checkOutTime: time);
  }

  Future<bool> _checkLocationAccess(Slot slot) async {
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
      if (!serviceEnabled) {
        _showError('Bitte aktiviere die Standortdienste (GPS) am Handy.');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Standort-Berechtigung wurde verweigert. Einchecken nicht möglich.');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showError('GPS-Berechtigung ist dauerhaft deaktiviert. Bitte in den Handy-Einstellungen freigeben.');
        return false;
      }

      // Final measurement
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // ANTI-SPOOFING CHECK
      if (position.isMocked) {
        if (AclService().isAdmin) {
          final confirmMock = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                   Icon(Icons.warning_amber_rounded, color: Colors.orange),
                   SizedBox(width: 10),
                   Text('Entwickler-Modus'),
                ],
              ),
              content: const Text(
                'Ein vorgetäuschter Standort (Mock-Location) wurde erkannt.\n\n'
                'Möchten Sie diesen Standort für einen Testlauf trotzdem verwenden? (Nur für Admins)'
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  child: const Text('Ja, Mock nutzen'),
                ),
              ],
            ),
          );
          if (confirmMock != true) return false;
        } else {
          _showError('Sicherheitsfehler: Ein vorgetäuschter Standort wurde erkannt. Check-In blockiert.');
          // Flag the cheating persistently in EspoCRM
          try {
            await _apiService.patchSlot(slot.id, {'mockStandort': true});
          } catch (e) {
            debugPrint('Failed to flag mock location on server: $e');
          }
          return false;
        }
      }

      double distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        targetLat,
        targetLon,
      );

      if (distanceInMeters > allowedRadius.toDouble()) {
        _showLocationDeniedDialog(distanceInMeters, allowedRadius.toDouble(), slot);
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('GPS Error: $e');
      _showError('GPS-Fehler: Der Standort konnte nicht ermittelt werden.');
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Keine Navigations-App gefunden.'), backgroundColor: Colors.orange),
          );
        }
      }
    } catch (e) {
      debugPrint('Navigation launch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Navigations-App gefunden.'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  void _showLocationDeniedDialog(double distance, double allowed, Slot slot) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.red),
            SizedBox(width: 10),
            Text('Check-In verweigert'),
          ],
        ),
        content: Text(
          'Sie befinden sich nicht am Einsatzobjekt.\n\n'
          'Aktuelle Entfernung: ${distance.toStringAsFixed(1)} Meter.\n'
          'Maximal erlaubt: ${allowed.toStringAsFixed(1)} Meter.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          if (AclService().isAdmin)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _performCheckIn(slot);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
              child: const Text('Trotzdem einloggen (Admin)'),
            ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _syncSlotToServer(Slot slot, {String? checkInTime, String? checkOutTime}) async {
    final Map<String, dynamic> data = {};
    String? datePart;
    if (slot.dateStart != null && slot.dateStart!.contains(' ')) {
      datePart = slot.dateStart!.split(' ')[0];
    } else if (slot.dateStart != null) {
      datePart = slot.dateStart;
    }

    if (checkInTime != null) {
      data['checkin'] = checkInTime.isEmpty ? null : (datePart != null ? '$datePart $checkInTime:00' : null);
      if (checkInTime.isEmpty) {
        data['checkinstat'] = null;
      } else {
        bool isLate = false;
        if (slot.dateStart != null) {
          try {
            final startDt = DateFormat('yyyy-MM-dd HH:mm:ss').parse(slot.dateStart!);
            final parts = checkInTime.split(':');
            final checkDt = DateTime(startDt.year, startDt.month, startDt.day, int.parse(parts[0]), int.parse(parts[1]));
            if (checkDt.isAfter(startDt)) {
              isLate = true;
            }
          } catch (_) {}
        }
        data['checkinstat'] = isLate ? '🟡' : '🟢';
      }
    }
    if (checkOutTime != null) {
      data['checkout'] = checkOutTime.isEmpty ? null : (datePart != null ? '$datePart $checkOutTime:00' : null);
    }

    if (data.isNotEmpty) {
      try {
        final success = await _apiService.patchSlot(slot.id, data);
        if (success && mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Daten an EspoCRM übertragen'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        debugPrint('Sync Error: $e – Queuing for retry...');
        
        // Enqueue for automatic retry
        final desc = checkInTime != null 
            ? 'Check-In ${slot.angestellteName ?? slot.name} ($checkInTime)'
            : 'Check-Out ${slot.angestellteName ?? slot.name} ($checkOutTime)';
        await _syncQueue.enqueue(
          slotId: slot.id,
          data: data,
          description: desc,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('⏳ Kein Netz – Daten werden automatisch nachgesendet'),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Details',
                textColor: Colors.white,
                onPressed: _showSyncQueueStatus,
              ),
            ),
          );
        }
      }
    }
  }

  void _showSyncQueueStatus() async {
    final summary = await _syncQueue.getPendingSummary();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.sync, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          const Text('Ausstehende Synchronisierung'),
        ]),
        content: summary.isEmpty
            ? const Text('Alle Daten sind synchronisiert. ✅')
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: summary.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.pending, color: Colors.orange, size: 20),
                    title: Text(summary[i], style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Schließen'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _syncQueue.processQueue();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🔄 Synchronisierung wird erneut versucht...'), duration: Duration(seconds: 2)),
              );
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Jetzt synchronisieren'),
          ),
        ],
      ),
    );
  }

  bool _isLate(Slot slot) {
    if (!_checkedSlotIds.contains(slot.id)) return false;
    final checkTime = _checkedSlotTimes[slot.id];
    if (checkTime == null || slot.dateStart == null) return false;
    
    try {
      final startDt = DateFormat('yyyy-MM-dd HH:mm:ss').parse(slot.dateStart!);
      final parts = checkTime.split(':');
      final checkDt = DateTime(startDt.year, startDt.month, startDt.day, int.parse(parts[0]), int.parse(parts[1]));
      return checkDt.isAfter(startDt);
    } catch (_) {
      return false;
    }
  }


  void _applyFilters() {
    final format = DateFormat('yyyy-MM-dd HH:mm:ss');
    List<Slot> filtered = List.from(_allSlots);

    if (_selectedAngestellte != null) {
      filtered = filtered.where((s) => s.angestellteName == _selectedAngestellte).toList();
    }
    if (_selectedObjekt != null) {
      filtered = filtered.where((s) => s.objekteName == _selectedObjekt).toList();
    }
    if (_selectedAccount != null) {
      filtered = filtered.where((s) => s.accountName == _selectedAccount).toList();
    }
    if (_selectedDateRange != null) {
      filtered = filtered.where((s) {
        if (s.dateStart == null) return false;
        try {
          final cleanStr = s.dateStart!.trim();
          // Extract just the 'YYYY-MM-DD' part safely to avoid any time format exceptions
          if (cleanStr.length < 10) return false;
          
          final datePart = cleanStr.substring(0, 10);
          final parts = datePart.split('-');
          if (parts.length != 3) return false;
          
          final startDay = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );

          final rangeStart = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
          final rangeEnd = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day);

          return !startDay.isBefore(rangeStart) && !startDay.isAfter(rangeEnd);
        } catch (e) {
          debugPrint('Date parse exception for slot ${s.name}: $e');
          return false;
        }
      }).toList();
    }

    setState(() => _filteredSlots = filtered);
  }

  void _clearFilters() {
    final bool didHaveDateRange = _selectedDateRange != null;
    setState(() {
      _selectedAngestellte = null;
      _selectedObjekt = null;
      _selectedAccount = null;
      _selectedDateRange = null;
    });
    
    // If we changed dates, we MUST refetch from the API to prevent sticking to specific date queries
    if (didHaveDateRange) {
      _loadSlots();
    } else {
      _applyFilters();
    }
  }

  bool get _hasActiveFilters =>
      _selectedAngestellte != null ||
      _selectedObjekt != null ||
      _selectedAccount != null ||
      _selectedDateRange != null;

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _selectedDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now.add(const Duration(days: 30)),
          ),
      locale: const Locale('de', 'DE'),
    );
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _isLoading = true;
      });
      // Fetch specifically for the selected date range to ensure complete data
      final slots = await _apiService.getSlots(startDate: picked.start, endDate: picked.end);
      if (mounted) {
        setState(() {
          _allSlots = slots;
          _isLoading = false;
        });
        _applyFilters();
      }
    }
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.blue.shade700;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.blue.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('dd.MM.yyyy HH:mm');
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schichten'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          // Sync queue indicator
          if (_pendingSyncCount > 0)
            IconButton(
              icon: Badge(
                label: Text('$_pendingSyncCount', style: const TextStyle(fontSize: 10)),
                backgroundColor: Colors.orange,
                child: const Icon(Icons.sync_problem),
              ),
              tooltip: '$_pendingSyncCount ausstehende Synchronisierungen',
              onPressed: _showSyncQueueStatus,
            ),
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: _showPresetsSheet,
            tooltip: 'Filter-Vorlagen',
          ),
          if (AclService().isAdmin) ...[
            IconButton(
              icon: Icon(_isBulkMode ? Icons.close : Icons.library_add_check),
              tooltip: _isBulkMode ? 'Abbrechen' : 'Mehrfachauswahl',
              onPressed: () {
                setState(() {
                  _isBulkMode = !_isBulkMode;
                  _bulkSelectedIds.clear();
                });
              },
            ),
          ],
          if (_hasActiveFilters)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              onPressed: _clearFilters,
              tooltip: 'Filter zurücksetzen',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSlots,
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: _selectedDateRange != null
                        ? '${DateFormat('dd.MM').format(_selectedDateRange!.start)} - ${DateFormat('dd.MM').format(_selectedDateRange!.end)}'
                        : 'Zeitraum',
                    icon: Icons.date_range,
                    isActive: _selectedDateRange != null,
                    onTap: _pickDateRange,
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: _selectedAngestellte ?? 'Angestellte',
                    icon: Icons.person,
                    isActive: _selectedAngestellte != null,
                    onTap: () => _showFilterBottomSheet(
                      'Angestellte wählen',
                      _angestellteOptions,
                      _selectedAngestellte,
                      (val) {
                        setState(() => _selectedAngestellte = val);
                        _applyFilters();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: _selectedObjekt ?? 'Objekt',
                    icon: Icons.business,
                    isActive: _selectedObjekt != null,
                    onTap: () => _showFilterBottomSheet(
                      'Objekt wählen',
                      _objekteOptions,
                      _selectedObjekt,
                      (val) {
                        setState(() => _selectedObjekt = val);
                        _applyFilters();
                      },
                    ),
                  ),
                  if (AclService.isAdminApp) ...[
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: _selectedAccount ?? 'Kunde',
                    icon: Icons.apartment,
                    isActive: _selectedAccount != null,
                    onTap: () => _showFilterBottomSheet(
                      'Kunde wählen',
                      _accountOptions,
                      _selectedAccount,
                      (val) {
                        setState(() => _selectedAccount = val);
                        _applyFilters();
                      },
                    ),
                  ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Text(
                    '${_filteredSlots.length} Schichten',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_hasActiveFilters)
                    Text(
                      ' (von ${_allSlots.length})',
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
                      ),
                    ),
                ],
              ),
            ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSlots.isEmpty
                    ? const Center(child: Text('Keine Schichten gefunden.'))
                    : RefreshIndicator(
                        onRefresh: _loadSlots,
                        child: ListView.builder(
                          itemCount: _filteredSlots.length,
                          itemBuilder: (context, index) {
                            final slot = _filteredSlots[index];
                            final color = _parseColor(slot.firmaFarbcode);

                            DateTime? startDt;
                            DateTime? endDt;
                            try {
                              if (slot.dateStart != null) startDt = DateFormat('yyyy-MM-dd HH:mm:ss').parse(slot.dateStart!);
                              if (slot.dateEnd != null) endDt = DateFormat('yyyy-MM-dd HH:mm:ss').parse(slot.dateEnd!);
                            } catch (_) {}

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: IntrinsicHeight(
                                child: Row(
                                  children: [
                                    if (_isBulkMode)
                                      Checkbox(
                                        value: _bulkSelectedIds.contains(slot.id),
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _bulkSelectedIds.add(slot.id);
                                            } else {
                                              _bulkSelectedIds.remove(slot.id);
                                            }
                                          });
                                        },
                                      ),
                                    Container(
                                      width: 6,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(12),
                                          bottomLeft: Radius.circular(12),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: InkWell(
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(12),
                                          bottomLeft: Radius.circular(12),
                                        ),
                                        onTap: () => _showSlotDetails(slot),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if ((slot.bewacherID != null && slot.bewacherID!.isNotEmpty) || (slot.personalausweisnummer != null && slot.personalausweisnummer!.isNotEmpty))
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 6),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey.shade200,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      (slot.bewacherID != null && slot.bewacherID!.isNotEmpty)
                                                          ? 'ID: ${slot.bewacherID}'
                                                          : 'Ausweis: ${slot.personalausweisnummer}',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.grey.shade700,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    slot.name,
                                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                                if (slot.stundenanzahl != null)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: color.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      '${slot.stundenanzahl!.toStringAsFixed(1)}h',
                                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            // Time
                                            if (startDt != null && endDt != null)
                                              Row(
                                                children: [
                                                  Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${format.format(startDt)} – ${DateFormat('HH:mm').format(endDt)}',
                                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                                  ),
                                                ],
                                              ),
                                            const SizedBox(height: 4),
                                            // Objekt
                                            if (slot.objekteName != null)
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Icon(Icons.location_on, size: 14, color: Colors.grey.shade600),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: InkWell(
                                                      onTap: () {
                                                        final addr = [
                                                          slot.neueobjektstrasse ?? slot.firmastrasse,
                                                          if (slot.neueobjektplz != null || slot.firmaplz != null) 
                                                            '${slot.neueobjektplz ?? slot.firmaplz} ${slot.neueobjektort ?? slot.firmaort}'
                                                          else 
                                                            (slot.neueobjektort ?? slot.firmaort)
                                                        ].where((s) => s != null && s.toString().isNotEmpty).join(', ');
                                                        _launchNavigation(addr);
                                                      },
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          RichText(
                                                            text: TextSpan(
                                                              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                                              children: [
                                                                const TextSpan(text: 'Objekt: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                TextSpan(text: slot.objekteName!, style: const TextStyle(fontWeight: FontWeight.w500)),
                                                              ],
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                          if (slot.neueobjektstrasse != null || slot.neueobjektort != null || slot.firmaort != null)
                                                            Padding(
                                                              padding: const EdgeInsets.only(top: 2),
                                                              child: Text(
                                                                [
                                                                  slot.neueobjektstrasse ?? slot.firmastrasse,
                                                                  if (slot.neueobjektplz != null || slot.firmaplz != null) 
                                                                    '${slot.neueobjektplz ?? slot.firmaplz} ${slot.neueobjektort ?? slot.firmaort}'
                                                                  else 
                                                                    (slot.neueobjektort ?? slot.firmaort)
                                                                ].where((s) => s != null && s.toString().isNotEmpty).join(', '),
                                                                style: TextStyle(
                                                                  fontSize: 12, 
                                                                  color: Theme.of(context).primaryColor,
                                                                  fontWeight: FontWeight.w500,
                                                                  decoration: TextDecoration.underline,
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            // Account (nur Admin-App)
                                            if (AclService.isAdminApp && slot.accountName != null) ...[
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Icon(Icons.apartment, size: 14, color: Colors.grey.shade600),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: RichText(
                                                      text: TextSpan(
                                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                                        children: [
                                                          const TextSpan(text: 'Kunde: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                                          TextSpan(text: slot.accountName!),
                                                        ],
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            // Position
                                            if (slot.positionsname != null && slot.positionsname!.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Icon(Icons.badge, size: 14, color: Colors.grey.shade600),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: RichText(
                                                      text: TextSpan(
                                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                                        children: [
                                                          const TextSpan(text: 'Position: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                                          TextSpan(text: slot.positionsname!),
                                                        ],
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            // Mitarbeiter / Kooperationspartner
                                            if (slot.angestellteName != null) ...[
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Icon(Icons.person, size: 14, color: Colors.grey.shade600),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: RichText(
                                                      text: TextSpan(
                                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                                        children: [
                                                          const TextSpan(text: 'Mitarbeiter: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                                          TextSpan(text: slot.angestellteName!),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            if (slot.kooperationspartnerName != null && slot.kooperationspartnerName!.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Icon(Icons.handshake, size: 14, color: Colors.grey.shade600),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: RichText(
                                                      text: TextSpan(
                                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                                        children: [
                                                          const TextSpan(text: 'Partner: ', style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                                                          TextSpan(text: slot.kooperationspartnerName!, style: const TextStyle(fontStyle: FontStyle.italic)),
                                                        ],
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                    ),
                                    // Attendance Tracking (Now enabled for all users)
                                    Padding(
                                        padding: const EdgeInsets.only(right: 8.0, left: 4),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            // IN
                                            GestureDetector(
                                              onTap: () => _toggleSlotChecked(slot, !_checkedSlotIds.contains(slot.id)),
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  Icon(
                                                    _checkedSlotIds.contains(slot.id) ? Icons.login : Icons.login_outlined,
                                                    size: 24,
                                                    color: _checkedSlotIds.contains(slot.id) ? (_isLate(slot) ? Colors.red : Colors.green) : Colors.grey.shade400,
                                                  ),
                                                  if (_checkedSlotIds.contains(slot.id))
                                                    Positioned(
                                                      right: -2,
                                                      top: -2,
                                                      child: Icon(Icons.check_circle, size: 10, color: _isLate(slot) ? Colors.red : Colors.green),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            if (_checkedSlotIds.contains(slot.id) && _checkedSlotTimes.containsKey(slot.id))
                                              Text(
                                                _checkedSlotTimes[slot.id]!,
                                                style: TextStyle(
                                                  fontSize: 9, 
                                                  fontWeight: FontWeight.bold, 
                                                  color: _isLate(slot) ? Colors.red : Colors.green,
                                                ),
                                              ),
                                            const SizedBox(height: 10),
                                            // OUT
                                            GestureDetector(
                                              onTap: () => _toggleSlotOutChecked(slot, !_checkedSlotOutIds.contains(slot.id)),
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  Icon(
                                                    _checkedSlotOutIds.contains(slot.id) ? Icons.logout : Icons.logout_outlined,
                                                    size: 24,
                                                    color: _checkedSlotOutIds.contains(slot.id) ? Colors.orange : Colors.grey.shade400,
                                                  ),
                                                  if (_checkedSlotOutIds.contains(slot.id))
                                                    const Positioned(
                                                      right: -2,
                                                      top: -2,
                                                      child: Icon(Icons.check_circle, size: 10, color: Colors.orange),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            if (_checkedSlotOutIds.contains(slot.id) && _checkedSlotOutTimes.containsKey(slot.id))
                                              Text(
                                                _checkedSlotOutTimes[slot.id]!,
                                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange),
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: _isBulkMode && _bulkSelectedIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _showBulkEditDialog,
              backgroundColor: Theme.of(context).primaryColor,
              label: Text('${_bulkSelectedIds.length} ändern'),
              icon: const Icon(Icons.edit_calendar, color: Colors.white),
            )
          : null,
    );
  }

  void _showBulkEditDialog() {
    String? bulkIn;
    String? bulkOut;
    bool updateIn = false;
    bool updateOut = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mehrfachänderung (Präsenz)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: const Text('Check-In (Beginn) setzen'),
                value: updateIn,
                onChanged: (v) => setDialogState(() => updateIn = v!),
              ),
              if (updateIn)
                ListTile(
                  title: Text(bulkIn ?? '--:--'),
                  leading: const Icon(Icons.login),
                  onTap: () async {
                    final time = await _pickTime(context, bulkIn ?? '08:00');
                    if (time != null) setDialogState(() => bulkIn = time);
                  },
                ),
              const Divider(),
              CheckboxListTile(
                title: const Text('Check-Out (Ende) setzen'),
                value: updateOut,
                onChanged: (v) => setDialogState(() => updateOut = v!),
              ),
              if (updateOut)
                ListTile(
                  title: Text(bulkOut ?? '--:--'),
                  leading: const Icon(Icons.logout),
                  onTap: () async {
                    final time = await _pickTime(context, bulkOut ?? '16:00');
                    if (time != null) setDialogState(() => bulkOut = time);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: (!updateIn && !updateOut) ? null : () {
                Navigator.pop(context);
                _performBulkUpdate(
                  inTime: updateIn ? bulkIn : null,
                  outTime: updateOut ? bulkOut : null,
                );
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performBulkUpdate({String? inTime, String? outTime}) async {
    setState(() => _isLoading = true);
    int count = 0;
    try {
      for (var id in _bulkSelectedIds) {
        final slot = _allSlots.firstWhere((s) => s.id == id);
        final Map<String, dynamic> data = {};
        
        String? datePart;
        if (slot.dateStart != null && slot.dateStart!.contains(' ')) {
          datePart = slot.dateStart!.split(' ')[0];
        } else {
          datePart = slot.dateStart;
        }

        if (inTime != null) {
          data['checkin'] = inTime.isEmpty ? null : (datePart != null ? '$datePart $inTime:00' : null);
          data['checkinstat'] = inTime.isEmpty ? null : '🟢';
          _checkedSlotIds.add(id);
          _checkedSlotTimes[id] = inTime;
        }
        if (outTime != null) {
          data['checkout'] = outTime.isEmpty ? null : (datePart != null ? '$datePart $outTime:00' : null);
          _checkedSlotOutIds.add(id);
          _checkedSlotOutTimes[id] = outTime;
        }

        if (data.isNotEmpty) {
          await _apiService.patchSlot(id, data);
          count++;
        }
      }
      
      _saveLocalPresence();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count Schichten erfolgreich aktualisiert (Bulk).'), backgroundColor: Colors.green),
      );
    } catch (e) {
      debugPrint('Bulk Update Error: $e');
      _showError('Bulk-Update fehlgeschlagen: $e');
    } finally {
      setState(() {
        _isBulkMode = false;
        _bulkSelectedIds.clear();
        _isLoading = false;
      });
      _loadSlots();
    }
  }

  void _showSlotDetails(Slot slot) {
    final format = DateFormat('dd.MM.yyyy HH:mm');
    final color = _parseColor(slot.firmaFarbcode);

    DateTime? startDt;
    DateTime? endDt;
    try {
      if (slot.dateStart != null) startDt = DateFormat('yyyy-MM-dd HH:mm:ss').parse(slot.dateStart!);
      if (slot.dateEnd != null) endDt = DateFormat('yyyy-MM-dd HH:mm:ss').parse(slot.dateEnd!);
    } catch (_) {}

    // On-demand: clothing info is not in the list select, load it lazily
    String? kleidungInfo = slot.neueobjektkleidunganmerkung;
    bool kleidungLoaded = kleidungInfo != null && kleidungInfo.isNotEmpty;
    bool kleidungLoading = !kleidungLoaded;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // Trigger async load of full slot details (only once)
          if (kleidungLoading) {
            _apiService.getSlotById(slot.id).then((fullSlot) {
              if (fullSlot != null) {
                final info = fullSlot.neueobjektkleidunganmerkung;
                setModalState(() {
                  kleidungInfo = (info != null && info.isNotEmpty) ? info : null;
                  kleidungLoaded = true;
                  kleidungLoading = false;
                });
              } else {
                setModalState(() {
                  kleidungLoading = false;
                  kleidungLoaded = true;
                });
              }
            }).catchError((_) {
              setModalState(() {
                kleidungLoading = false;
                kleidungLoaded = true;
              });
            });
            kleidungLoading = false; // Prevent re-triggering
          }

          final isChecked = _checkedSlotIds.contains(slot.id);
          final checkInTime = _checkedSlotTimes[slot.id] ?? '--:--';

          return AlertDialog(
            title: Text(slot.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (startDt != null)
                    _buildDetailRow(Icons.access_time, 'Beginn', format.format(startDt)),
                  if (endDt != null)
                    _buildDetailRow(Icons.timer_off_outlined, 'Ende', format.format(endDt)),
                  if (slot.stundenanzahl != null)
                    _buildDetailRow(Icons.hourglass_bottom, 'Stunden', '${slot.stundenanzahl!.toStringAsFixed(1)} h'),
                  
                  const Divider(height: 24),
                  
                  if (AclService.isAdminApp && slot.accountName != null)
                    _buildDetailRow(Icons.business, 'Kunde', slot.accountName!),
                  if (slot.objekteName != null)
                    _buildDetailRow(
                      Icons.location_on, 
                      'Objekt', 
                      slot.objekteName!,
                      onTap: () {
                        final addr = [
                          slot.neueobjektstrasse ?? slot.firmastrasse,
                          if (slot.neueobjektplz != null || slot.firmaplz != null) 
                            '${slot.neueobjektplz ?? slot.firmaplz} ${slot.neueobjektort ?? slot.firmaort}'
                          else 
                            (slot.neueobjektort ?? slot.firmaort)
                        ].where((s) => s != null && s.toString().isNotEmpty).join(', ');
                        _launchNavigation(addr);
                      },
                    ),
                  if (slot.positionsname != null)
                    _buildDetailRow(Icons.work, 'Position', slot.positionsname!),
                  if (kleidungInfo != null && kleidungInfo!.isNotEmpty)
                    _buildDetailRow(Icons.checkroom, 'Arbeitskleidung', kleidungInfo!),
                  if (!kleidungLoaded)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Kleidung wird geladen...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ]),
                    ),
                  
                  if (slot.angestellteName != null || slot.kooperationspartnerName != null) ...[
                    const Divider(height: 24),
                    if (slot.angestellteName != null)
                      _buildDetailRow(Icons.person, 'Mitarbeiter', slot.angestellteName!),
                    if (slot.kooperationspartnerName != null && slot.kooperationspartnerName!.isNotEmpty)
                      _buildDetailRow(Icons.handshake, 'Partner', slot.kooperationspartnerName!),
                  ],

                  // Admin Presence Tracking
                  if (AclService().isAdmin) ...[
                    const Divider(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Admin Tracking', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 12),
                          // CHECK IN
                          _buildTrackingRow(
                            label: 'Check-In (Beginn)',
                            icon: Icons.login,
                            color: Colors.green,
                            isChecked: _checkedSlotIds.contains(slot.id),
                            time: _checkedSlotTimes[slot.id] ?? '--:--',
                            onToggle: (val) {
                              _toggleSlotChecked(slot, val);
                              setModalState(() {});
                            },
                            onTimeTap: () async {
                              final time = await _pickTime(context, _checkedSlotTimes[slot.id] ?? '--:--');
                              if (time != null) {
                                _updateCheckInTime(slot, time);
                                setModalState(() {});
                              }
                            },
                            effectiveLabel: () {
                              if (!_checkedSlotIds.contains(slot.id)) return null;
                              final checkTime = _checkedSlotTimes[slot.id];
                              if (checkTime == null || startDt == null) return null;
                              
                              try {
                                final parts = checkTime.split(':');
                                final checkDt = DateTime(startDt.year, startDt.month, startDt.day, int.parse(parts[0]), int.parse(parts[1]));
                                
                                if (checkDt.isAfter(startDt)) {
                                  return 'Angepasster Beginn: ${checkTime}';
                                } else {
                                  return 'Pünktlich (Beginn: ${DateFormat('HH:mm').format(startDt)})';
                                }
                              } catch (_) { return null; }
                            }(),
                            effectiveColor: _isLate(slot) ? Colors.red : Colors.green,
                          ),
                          const SizedBox(height: 12),
                          // CHECK OUT
                          _buildTrackingRow(
                            label: 'Check-Out (Ende)',
                            icon: Icons.logout,
                            color: Colors.orange,
                            isChecked: _checkedSlotOutIds.contains(slot.id),
                            time: _checkedSlotOutTimes[slot.id] ?? '--:--',
                            onToggle: (val) {
                              _toggleSlotOutChecked(slot, val);
                              setModalState(() {});
                            },
                            onTimeTap: () async {
                              final time = await _pickTime(context, _checkedSlotOutTimes[slot.id] ?? '--:--');
                              if (time != null) {
                                _updateCheckOutTime(slot, time);
                                setModalState(() {});
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
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

  Future<String?> _pickTime(BuildContext context, String initialTime) async {
    final tParts = initialTime.split(':');
    final initial = tParts.length == 2 
        ? TimeOfDay(hour: int.parse(tParts[0]), minute: int.parse(tParts[1]))
        : TimeOfDay.now();

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return null;
  }

  Widget _buildTrackingRow({
    required String label,
    required IconData icon,
    required Color color,
    required bool isChecked,
    required String time,
    required ValueChanged<bool?> onToggle,
    required VoidCallback onTimeTap,
    String? effectiveLabel,
    Color? effectiveColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: isChecked,
              activeColor: color,
              onChanged: onToggle,
            ),
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            const Spacer(),
            if (isChecked)
              InkWell(
                onTap: onTimeTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        time, 
                        style: TextStyle(
                          fontWeight: FontWeight.bold, 
                          color: (effectiveColor != null && isChecked) ? effectiveColor : null
                        )
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (effectiveLabel != null)
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Text(
              effectiveLabel,
              style: TextStyle(
                fontSize: 11, 
                color: effectiveColor ?? color, 
                fontStyle: FontStyle.italic, 
                fontWeight: FontWeight.bold
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                  Text(
                    value, 
                    style: TextStyle(
                      fontSize: 14, 
                      fontWeight: FontWeight.w500,
                      color: onTap != null ? Theme.of(context).primaryColor : null,
                      decoration: onTap != null ? TextDecoration.underline : null,
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

  void _showPresetsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Gespeicherte Filter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showSavePresetDialog();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Aktuellen speichern'),
                  ),
                ],
              ),
              const Divider(),
              if (_presets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Keine Vorlagen gespeichert.'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _presets.length,
                    itemBuilder: (context, index) {
                      final p = _presets[index];
                      return ListTile(
                        leading: const Icon(Icons.label_outline),
                        title: Text(p['name']),
                        subtitle: Text([
                          if (p['relativeRange'] == 'today') 'Heute',
                          if (p['relativeRange'] == 'current_month') 'Aktueller Monat',
                          if (p['relativeRange'] == 'next_month') 'Nächster Monat',
                          if (p['angestellte'] != null) p['angestellte'],
                          if (AclService.isAdminApp && p['account'] != null) 'Kunde: ${p['account']}',
                        ].join(' | ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                _defaultPresetName == p['name'] ? Icons.push_pin : Icons.push_pin_outlined,
                                color: _defaultPresetName == p['name'] ? Theme.of(context).colorScheme.secondary : Colors.grey,
                                size: 20,
                              ),
                              onPressed: () {
                                if (_defaultPresetName == p['name']) {
                                  _setDefaultPreset(null);
                                } else {
                                  _setDefaultPreset(p['name']);
                                }
                                Navigator.pop(ctx);
                                _showPresetsSheet();
                              },
                              tooltip: 'Als Standard setzen',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                              onPressed: () async {
                                if (_defaultPresetName == p['name']) {
                                  _setDefaultPreset(null);
                                }
                                setState(() {
                                  _presets.removeAt(index);
                                });
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setString('slot_presets', json.encode(_presets));
                                Navigator.pop(ctx);
                                _showPresetsSheet();
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyPreset(p);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showSavePresetDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter speichern'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Name der Vorlage (z.B. Nur Meine)',
            labelText: 'Name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context);
                _saveCurrentAsPreset(controller.text.trim());
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  void _showFilterBottomSheet(
    String title,
    List<String> options,
    String? currentSelection,
    Function(String?) onSelect,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final filteredOptions = options
                .where((opt) => opt.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();
                
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          if (currentSelection != null)
                            TextButton(
                              onPressed: () {
                                onSelect(null);
                                Navigator.pop(ctx);
                              },
                              child: const Text('Zurücksetzen'),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Suchen...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.grey.shade200,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        ),
                        onChanged: (val) {
                          setModalState(() {
                            searchQuery = val;
                          });
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: filteredOptions.length,
                        itemBuilder: (_, i) {
                          final option = filteredOptions[i];
                          final isSelected = option == currentSelection;
                          return ListTile(
                            title: Text(option),
                            trailing: isSelected ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                            selected: isSelected,
                            onTap: () {
                              onSelect(option);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Theme.of(context).primaryColor.withOpacity(0.15) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Theme.of(context).primaryColor : Colors.grey.shade400,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isActive ? Theme.of(context).primaryColor : Colors.grey.shade600),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? Theme.of(context).primaryColor : Colors.grey.shade800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              Icon(Icons.close, size: 14, color: Theme.of(context).primaryColor),
            ],
          ],
        ),
      ),
    );
  }
}
