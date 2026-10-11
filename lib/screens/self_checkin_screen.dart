import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import '../models/slot.dart';
import '../services/api_service.dart';
import '../services/acl_service.dart';
import '../services/secure_storage_service.dart';
import '../services/checkin_state_service.dart';
import '../services/location_service.dart';
import '../services/sync_queue_service.dart';
import '../core/constants.dart';
import '../utils/espo_date.dart';

/// Self-Service Check-In Screen für Mitarbeiter & Einsatzleiter — inspiriert vom stationären Check-in-Terminal.
/// Da der Mitarbeiter in der App bereits authentifiziert ist, wird KEIN Barcode-Scanner benötigt.
/// Reguläre Mitarbeiter sehen direkt ihre heutigen Schichten.
/// Einsatzleiter und Admins sehen zudem die Schichten ihres Teams am Einsatzort und können diese vor Ort ein- und auschecken.
class SelfCheckinScreen extends StatefulWidget {
  const SelfCheckinScreen({super.key});

  @override
  State<SelfCheckinScreen> createState() => _SelfCheckinScreenState();
}

class _SelfCheckinScreenState extends State<SelfCheckinScreen> with WidgetsBindingObserver {
  final ApiService _api = ApiService();
  final AclService _acl = AclService();
  final LocationService _location = LocationService();
  final SyncQueueService _syncQueue = SyncQueueService();
  final SecureStorageService _storage = SecureStorageService();

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  Timer? _autoRefreshTimer;

  List<Slot> _allRelevantSlots = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  String? _currentAngestellteId;

  // Tabs für Admins & Einsatzleiter: 0 = Meine Schichten, 1 = Einsatzleitung / Team
  int _selectedTab = 0;
  String _searchQuery = '';

  // Slot-spezifischer Ladezustand (verhindert globales Layout-Jumping)
  String? _processingSlotId;

  // Lokaler Check-In-Status (gespeichert für nahtlosen Offline- und Online-Betrieb)
  Set<String> _checkedIn = {};
  Set<String> _checkedOut = {};
  Map<String, String> _checkedTimes = {};
  Map<String, String> _checkedOutTimes = {};
  final Map<String, String> _slotAmpeln = {}; // cI Ampel (🟢 🟡 🔴)

  bool get _isProcessing => _processingSlotId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _acl.refresh();
    _searchCtrl.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchCtrl.text.trim().toLowerCase();
        });
      }
    });
    CheckinStateService().init();
    CheckinStateService().addListener(_onCheckinStateChanged);
    _initAndLoad();
    _startAutoRefresh();
  }

  void _onCheckinStateChanged() {
    if (mounted) {
      setState(() {
        _checkedIn = CheckinStateService().checkedInSlotIds.toSet();
        _checkedOut = CheckinStateService().checkedOutSlotIds.toSet();
        _checkedTimes = Map.from(CheckinStateService().checkedInTimes);
        _checkedOutTimes = Map.from(CheckinStateService().checkedOutTimes);
      });
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (mounted && !_isProcessing) {
        _loadTodaysSlots(silent: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted && !_isProcessing) {
        _loadTodaysSlots(silent: true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CheckinStateService().removeListener(_onCheckinStateChanged);
    _autoRefreshTimer?.cancel();
    _scrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    _currentAngestellteId = await _storage.getAngestellteId();
    await _loadLocalState();
    await _loadTodaysSlots();
  }

  Future<void> _loadLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _checkedIn = (prefs.getStringList('admin_checked_slots') ?? []).toSet();
      _checkedOut = (prefs.getStringList('admin_checked_out_slots') ?? []).toSet();
      final inJson = prefs.getString('admin_checked_times');
      final outJson = prefs.getString('admin_checked_out_times');
      try {
        if (inJson != null && inJson.trim().isNotEmpty) {
          _checkedTimes = Map<String, String>.from(json.decode(inJson));
        }
      } catch (e) {
        debugPrint('SelfCheckin: Error parsing admin_checked_times: $e');
      }
      try {
        if (outJson != null && outJson.trim().isNotEmpty) {
          _checkedOutTimes = Map<String, String>.from(json.decode(outJson));
        }
      } catch (e) {
        debugPrint('SelfCheckin: Error parsing admin_checked_out_times: $e');
      }
    });
  }

  Future<void> _saveLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('admin_checked_slots', _checkedIn.toList());
    await prefs.setStringList('admin_checked_out_slots', _checkedOut.toList());
    await prefs.setString('admin_checked_times', json.encode(_checkedTimes));
    await prefs.setString('admin_checked_out_times', json.encode(_checkedOutTimes));
  }

  /// Lädt die heutigen Schichten. Wenn bereits Schichten vorhanden sind,
  /// wird die Liste im Hintergrund aktualisiert, um die Scrollposition nicht zu verlieren.
  Future<void> _loadTodaysSlots({bool silent = false}) async {
    if (_allRelevantSlots.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else if (!silent) {
      setState(() {
        _isRefreshing = true;
      });
    }

    try {
      final now = DateTime.now();

      // Puffer für Nachtschichten: Gestern Mittag bis morgen Mittag
      // getCheckinSlots holt für Einsatzleiter automatisch auch die Team-Schichten!
      final allSlots = await _api.getCheckinSlots(
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 1)),
      );

      // Schichten filtern:
      // - Eigene Schichten (angestellteId == currentAngestellteId)
      // - Schichten als Einsatzleiter (einsatzleiterId == currentAngestellteId oder canEditOnr)
      // - Alle Schichten (bei Admin)
      final relevantSlots = allSlots.where((s) {
        if (!_acl.isAdmin && _currentAngestellteId != null) {
          final isMySlot = s.angestellteId == _currentAngestellteId;
          final isMyElSlot = s.isEinsatzleiter(_currentAngestellteId) || (s.canEditOnr == true);
          if (!isMySlot && !isMyElSlot) {
            return false;
          }
        }

        if (s.dateStart == null) return false;
        // Schicht findet heute statt (inkl. Nachtschichten über Mitternacht)
        return isSlotOnLocalDate(s.dateStart, s.dateEnd, now);
      }).toList();

      relevantSlots.sort((a, b) => (a.dateStart ?? '').compareTo(b.dateStart ?? ''));

      // Backend-Werte in lokale Ampel-Map übernehmen
      for (final s in relevantSlots) {
        if (s.cI != null && s.cI!.isNotEmpty) {
          _slotAmpeln[s.id] = s.cI!;
        }
        if (s.checkin != null && s.checkin!.isNotEmpty) {
          _checkedIn.add(s.id);
          final localIn = formatUtcToLocalTime(s.checkin);
          if (localIn != null) {
            _checkedTimes[s.id] = localIn;
          }
        }
        if (s.checkout != null && s.checkout!.isNotEmpty) {
          _checkedOut.add(s.id);
          final localOut = formatUtcToLocalTime(s.checkout);
          if (localOut != null) {
            _checkedOutTimes[s.id] = localOut;
          }
        }
      }

      CheckinStateService().syncSlotsFromServer(relevantSlots);
      await CheckinStateService().refreshGlobalConfig();

      if (!mounted) return;
      setState(() {
        _allRelevantSlots = relevantSlots;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_allRelevantSlots.isEmpty) {
          _errorMessage = 'Fehler beim Laden: $e';
        }
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  bool get _hasSupervisorCapabilities {
    if (_acl.isAdmin) return true;
    if (_currentAngestellteId == null) return false;
    return _allRelevantSlots.any((s) => s.isEinsatzleiter(_currentAngestellteId) || (s.canEditOnr == true));
  }

  List<Slot> get _displayedSlots {
    List<Slot> baseList;

    if (!_hasSupervisorCapabilities) {
      // Normaler Mitarbeiter: Sieht nur seine eigenen Schichten
      baseList = _allRelevantSlots.where((s) => s.angestellteId == _currentAngestellteId).toList();
    } else {
      // Supervisor / Admin:
      if (_selectedTab == 0) {
        // Tab: Meine Schichten
        baseList = _allRelevantSlots.where((s) => s.angestellteId == _currentAngestellteId).toList();
      } else {
        // Tab: Einsatzleitung / Team
        if (_acl.isAdmin) {
          baseList = _allRelevantSlots;
        } else {
          baseList = _allRelevantSlots.where((s) => s.isEinsatzleiter(_currentAngestellteId) || (s.canEditOnr == true)).toList();
        }
      }
    }

    if (_searchQuery.isEmpty) return baseList;

    return baseList.where((s) {
      final nameMatch = s.name.toLowerCase().contains(_searchQuery);
      final objMatch = s.objekteName?.toLowerCase().contains(_searchQuery) ?? false;
      final empMatch = s.angestellteName?.toLowerCase().contains(_searchQuery) ?? false;
      final posMatch = s.positionsname?.toLowerCase().contains(_searchQuery) ?? false;
      final onrMatch = s.oNr?.toLowerCase().contains(_searchQuery) ?? false;
      return nameMatch || objMatch || empMatch || posMatch || onrMatch;
    }).toList();
  }

  int get _mySlotsCount => _allRelevantSlots.where((s) => s.angestellteId == _currentAngestellteId).length;
  int get _teamSlotsCount => _acl.isAdmin
      ? _allRelevantSlots.length
      : _allRelevantSlots.where((s) => s.isEinsatzleiter(_currentAngestellteId) || (s.canEditOnr == true)).length;

  Future<void> _doCheckIn(Slot slot, {String? oNr}) async {
    if (_isProcessing) return;

    if (!CheckinStateService().isGloballyEnabled && !_acl.isAdmin) {
      _showErrorSnackbar('Check-In ist derzeit systemweit deaktiviert.');
      return;
    }

    // Wenn der Nutzer Einsatzleiter ist und für ein Teammitglied eincheckt,
    // bieten wir (wie im Terminal) ein modales Fenster zur Eingabe / Bestätigung der Ordnernummer an:
    final canEdit = slot.canUserEditOnr(_currentAngestellteId, isAdmin: _acl.isAdmin);
    final isTeamMember = slot.angestellteId != _currentAngestellteId;

    if (canEdit && isTeamMember && oNr == null) {
      final chosenOnr = await _showCheckinDialog(slot);
      if (chosenOnr == null) {
        // Abbruch durch Einsatzleiter
        return;
      }
      oNr = chosenOnr;
    }

    setState(() => _processingSlotId = slot.id);

    // 1. GPS Geofence Check über zentralen LocationService
    final gpsResult = await _location.checkGeofence(slot);
    if (!gpsResult.isSuccess) {
      if (mounted) setState(() => _processingSlotId = null);
      _showGpsErrorDialog(gpsResult, slot, isCheckIn: true, oNr: oNr);
      return;
    }

    await _executeCheckIn(slot, oNr: oNr);
  }

  /// Führt den tatsächlichen Check-In aus (nach GPS-Bestätigung oder Admin-Freigabe)
  Future<void> _executeCheckIn(Slot slot, {String? oNr}) async {
    setState(() => _processingSlotId = slot.id);

    final now = DateTime.now();
    final nowHHMM = DateFormat('HH:mm').format(now);
    final nowUtc = now.toUtc();
    final nowUtcStr = nowUtc.toIso8601String();

    HapticFeedback.mediumImpact();

    // Ampel lokal vorab berechnen
    String ampel = '🟢';
    if (slot.dateStart != null) {
      try {
        final startDt = DateFormat('yyyy-MM-dd HH:mm:ss').parseUtc(slot.dateStart!);
        final diffMins = (nowUtc.difference(startDt).inSeconds) / 60.0;
        if (diffMins > 0) {
          ampel = '🔴'; // Zu spät
        } else if (diffMins > -30) {
          ampel = '🟡'; // Knapp (innerhalb von 30 Min)
        } else {
          ampel = '🟢'; // Rechtzeitig
        }
      } catch (_) {}
    }

    try {
      final res = await CheckinStateService().performCheckIn(
        slot,
        oNr: oNr,
        customTimeUtc: nowUtcStr,
      );

      final isOffline = res['offline'] == true;
      final timeStr = res['time'] as String? ?? nowHHMM;
      final ampelRes = res['ampel'] as String? ?? ampel;

      if (mounted) {
        setState(() {
          _checkedIn.add(slot.id);
          _checkedTimes[slot.id] = timeStr;
          _slotAmpeln[slot.id] = ampelRes;
          if (oNr != null) {
            final idx = _allRelevantSlots.indexWhere((s) => s.id == slot.id);
            if (idx != -1) {
              _allRelevantSlots[idx] = _allRelevantSlots[idx].copyWith(
                oNr: oNr.isNotEmpty ? oNr : null,
              );
            }
          }
        });
        if (isOffline) {
          _showSuccessSnackbar('✅ Vor Ort eingecheckt! (Offline gespeichert – synchronisiert automatisch)');
        } else {
          final targetName = slot.angestellteName != null ? ' (${slot.angestellteName})' : '';
          final onrSuffix = (oNr != null && oNr.isNotEmpty) ? ' [Ordner #$oNr]' : '';
          _showSuccessSnackbar('✅ Eingecheckt um $timeStr Uhr ($ampelRes)$targetName$onrSuffix');
        }
      }
    } catch (e) {
      final errStr = e.toString();
      if (mounted) {
        _showErrorSnackbar('❌ Check-In abgelehnt / fehlgeschlagen: $errStr');
      }
    }

    if (mounted) setState(() => _processingSlotId = null);
  }

  Future<void> _doCheckOut(Slot slot) async {
    if (_isProcessing) return;

    final isOtherPerson = slot.angestellteName != null &&
        slot.angestellteId != null &&
        slot.angestellteId != _currentAngestellteId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.blueGrey),
            SizedBox(width: 8),
            Text('Schicht auschecken'),
          ],
        ),
        content: Text(isOtherPerson
            ? 'Möchtest du die Schicht von „${slot.angestellteName}“ (${slot.name}) jetzt auschecken?'
            : 'Möchtest du dich jetzt von der Schicht „${slot.name}“ auschecken?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryColor, foregroundColor: Colors.white),
            child: const Text('Jetzt Auschecken'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    setState(() => _processingSlotId = slot.id);

    // 1. GPS Geofence Check
    final gpsResult = await _location.checkGeofence(slot);
    if (!gpsResult.isSuccess) {
      if (mounted) setState(() => _processingSlotId = null);
      _showGpsErrorDialog(gpsResult, slot, isCheckIn: false);
      return;
    }

    await _executeCheckOut(slot);
  }

  /// Führt den tatsächlichen Check-Out aus (nach GPS-Bestätigung oder Admin-Freigabe)
  Future<void> _executeCheckOut(Slot slot) async {
    setState(() => _processingSlotId = slot.id);

    final now = DateTime.now();
    final nowHHMM = DateFormat('HH:mm').format(now);
    final nowUtc = now.toUtc();
    final nowUtcStr = nowUtc.toIso8601String();

    HapticFeedback.heavyImpact();

    try {
      final res = await CheckinStateService().performCheckOut(
        slot,
        customTimeUtc: nowUtcStr,
      );

      final isOffline = res['offline'] == true;
      final timeStr = res['time'] as String? ?? nowHHMM;

      if (mounted) {
        setState(() {
          _checkedOut.add(slot.id);
          _checkedOutTimes[slot.id] = timeStr;
        });
        final targetName = slot.angestellteName != null ? ' (${slot.angestellteName})' : '';
        if (isOffline) {
          _showSuccessSnackbar('👋 Ausgecheckt! (Offline gespeichert – synchronisiert automatisch)');
        } else {
          _showSuccessSnackbar('👋 Ausgecheckt um $timeStr Uhr$targetName');
        }
      }
    } catch (e) {
      final errStr = e.toString();
      if (mounted) {
        _showErrorSnackbar('❌ Check-Out abgelehnt / fehlgeschlagen: $errStr');
      }
    }

    if (mounted) setState(() => _processingSlotId = null);
  }

  void _showGpsErrorDialog(GpsCheckResult result, Slot slot, {required bool isCheckIn, String? oNr}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              result.status == GpsStatus.outsideRadius ? Icons.location_off : Icons.warning_amber_rounded,
              color: result.status == GpsStatus.outsideRadius ? Colors.red : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(result.status == GpsStatus.outsideRadius ? 'Nicht vor Ort' : 'Standort-Problem'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.message),
            if (result.address != null && result.address!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pin_drop, size: 18, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        result.address!,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_acl.isAdmin || _hasSupervisorCapabilities) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.admin_panel_settings, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _acl.isAdmin
                            ? 'Admin-Hinweis: Du kannst die Schicht bei Notfällen oder schlechtem GPS vor Ort freigeben.'
                            : 'Einsatzleiter-Hinweis: Du kannst dein Team bei Notfällen oder schlechtem GPS vor Ort freigeben.',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (result.address != null || result.targetLat != null)
            TextButton.icon(
              icon: const Icon(Icons.directions),
              label: const Text('Route'),
              onPressed: () {
                Navigator.pop(ctx);
                _location.openNavigation(
                  lat: result.targetLat,
                  lon: result.targetLon,
                  address: result.address,
                );
              },
            ),
          if (_acl.isAdmin || _hasSupervisorCapabilities)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                if (isCheckIn) {
                  _executeCheckIn(slot, oNr: oNr);
                } else {
                  _executeCheckOut(slot);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.check, size: 16),
              label: Text(_acl.isAdmin ? 'Admin-Freigabe' : 'EL-Freigabe'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryColor, foregroundColor: Colors.white),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  /// Öffnet ein modales Sheet (Terminal-Style) zur Eingabe / Bestätigung der Ordnernummer beim Team-Check-In
  Future<String?> _showCheckinDialog(Slot slot) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final initialOnr = slot.oNr ?? slot.empDefaultOnr ?? '';
    final ctrl = TextEditingController(text: initialOnr);

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.green.withOpacity(0.15),
                    child: const Icon(Icons.how_to_reg, color: Colors.green, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Team-Check-In',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        Text(
                          slot.angestellteName != null && slot.angestellteName!.isNotEmpty
                              ? slot.angestellteName!
                              : slot.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (slot.objekteName != null) ...[
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: isDark ? Colors.cyanAccent : AppConstants.primaryColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        slot.objekteName!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              Text(
                'Ordnernummer (optional)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'z. B. 42 oder 0071 (optional)',
                  helperText: 'Orientiert am Check-In Terminal. Freilassen falls nicht benötigt.',
                  prefixIcon: const Icon(Icons.folder_shared_outlined, size: 20),
                  filled: true,
                  fillColor: isDark ? Colors.white10 : Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text('Einchecken', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Dialog zum direkten Festlegen / Ändern der Ordnernummer durch den Einsatzleiter oder Admin
  Future<void> _showEditOnrDialog(Slot slot) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final initialOnr = slot.oNr ?? slot.empDefaultOnr ?? '';
    final ctrl = TextEditingController(text: initialOnr);

    final newOnr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.folder_shared_outlined, color: Colors.purple),
            SizedBox(width: 8),
            Text('Ordnernummer festlegen', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Für: ${slot.angestellteName != null && slot.angestellteName!.isNotEmpty ? slot.angestellteName! : slot.name}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Ordnernummer (optional)',
                hintText: 'z. B. 42 oder 0071',
                helperText: 'Freilassen, um die Ordnernummer zu entfernen.',
                prefixIcon: const Icon(Icons.badge, size: 18),
                filled: true,
                fillColor: isDark ? Colors.white10 : Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryColor, foregroundColor: Colors.white),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (newOnr == null) return;

    try {
      final success = await CheckinStateService().updateOrdnerNummer(slot.id, newOnr.isNotEmpty ? newOnr : null);
      if (success) {
        if (!mounted) return;
        setState(() {
          final idx = _allRelevantSlots.indexWhere((s) => s.id == slot.id);
          if (idx != -1) {
            _allRelevantSlots[idx] = _allRelevantSlots[idx].copyWith(
              oNr: newOnr.isNotEmpty ? newOnr : null,
            );
          }
        });
        _showSuccessSnackbar(newOnr.isNotEmpty ? '✅ Ordnernummer #$newOnr gespeichert' : '✅ Ordnernummer entfernt');
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackbar('❌ Fehler beim Speichern: $e');
    }
  }

  Widget _buildOrdnerNummerChip(Slot slot, bool isDark) {
    final canEdit = slot.canUserEditOnr(_currentAngestellteId, isAdmin: _acl.isAdmin);
    final hasOnr = slot.oNr != null && slot.oNr!.trim().isNotEmpty;

    if (!hasOnr && !canEdit) {
      // Normaler Mitarbeiter ohne Ordnernummer: Nichts anzeigen
      return const SizedBox.shrink();
    }

    if (hasOnr) {
      return InkWell(
        onTap: canEdit ? () => _showEditOnrDialog(slot) : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isDark ? Colors.purple.shade900.withOpacity(0.35) : Colors.purple.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.purpleAccent.shade100.withOpacity(0.5) : Colors.purple.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_shared_outlined,
                size: 13,
                color: isDark ? Colors.purpleAccent : Colors.purple.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                'Ordner #${slot.oNr}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.purpleAccent : Colors.purple.shade800,
                ),
              ),
              if (canEdit) ...[
                const SizedBox(width: 3),
                Icon(
                  Icons.edit,
                  size: 10,
                  color: isDark ? Colors.purpleAccent.withOpacity(0.7) : Colors.purple.shade400,
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Kein Onr, aber darf editieren (Einsatzleiter / Admin)
    return InkWell(
      onTap: () => _showEditOnrDialog(slot),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.grey.withOpacity(0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
            const SizedBox(width: 3),
            Text(
              'Ordner-Nr.',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white60 : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  void _showErrorSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(DateTime.now());
    final displayedList = _displayedSlots;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstempeln / Check-In'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_isRefreshing)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Schichten aktualisieren',
              onPressed: _loadTodaysSlots,
            ),
        ],
      ),
      body: Column(
        children: [
          // Datums-Header mit GPS-Status
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isDark ? const Color(0xFF1E293B) : AppConstants.primaryColor.withOpacity(0.06),
            child: Row(
              children: [
                Icon(Icons.today, color: isDark ? Colors.cyanAccent : AppConstants.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  now,
                  style: TextStyle(
                    color: isDark ? Colors.white : AppConstants.primaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'GPS-Geofence aktiv',
                    style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // Global Check-In Deaktiviert Banner (falls in EspoCRM deaktiviert)
          if (!CheckinStateService().isGloballyEnabled && !_acl.isAdmin)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade400),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Check-In ist derzeit systemweit pausiert oder deaktiviert.',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),

          // Umschalter für Einsatzleiter & Admins
          if (_hasSupervisorCapabilities) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isDark ? const Color(0xFF111827) : Colors.grey.shade100,
              child: Row(
                children: [
                  Expanded(
                    child: _buildTabButton(
                      title: 'Meine Schichten',
                      count: _mySlotsCount,
                      isSelected: _selectedTab == 0,
                      onTap: () => setState(() => _selectedTab = 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTabButton(
                      title: _acl.isAdmin ? 'Alle Schichten' : 'Einsatzleitung',
                      count: _teamSlotsCount,
                      isSelected: _selectedTab == 1,
                      onTap: () => setState(() => _selectedTab = 1),
                    ),
                  ),
                ],
              ),
            ),
            // Schnellsuchfeld bei Supervisor-Ansicht
            if (_selectedTab == 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Mitarbeiter oder Objekt suchen...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      filled: true,
                      fillColor: isDark ? Colors.white10 : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                      ),
                    ),
                  ),
                ),
              ),
          ],

          // Schichtenliste mit Erhalt der Scrollposition
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.red),
                              const SizedBox(height: 12),
                              Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton(onPressed: _loadTodaysSlots, child: const Text('Erneut versuchen')),
                            ],
                          ),
                        ),
                      )
                    : displayedList.isEmpty
                        ? _buildNoShifts()
                        : RefreshIndicator(
                            onRefresh: _loadTodaysSlots,
                            child: ListView.builder(
                              key: const PageStorageKey('self_checkin_list'),
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              itemCount: displayedList.length,
                              itemBuilder: (ctx, i) => _buildSlotCard(displayedList[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppConstants.primaryColor
                : (isDark ? Colors.white.withOpacity(0.05) : Colors.white),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppConstants.primaryColor : Colors.grey.withOpacity(0.2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withOpacity(0.25) : Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoShifts() {
    final hasSearch = _searchQuery.isNotEmpty;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(hasSearch ? Icons.search_off : Icons.event_available, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                hasSearch ? 'Keine Treffer für „$_searchQuery“' : 'Keine Schichten für heute',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                hasSearch ? 'Bitte Suchbegriff anpassen oder löschen.' : 'Für den gewählten Bereich liegen heute keine Schichten vor.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSlotCard(Slot slot) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isThisSlotProcessing = _processingSlotId == slot.id;
    final isIn = _checkedIn.contains(slot.id) || (slot.checkin != null && slot.checkin!.isNotEmpty);
    final isOut = _checkedOut.contains(slot.id) || (slot.checkout != null && slot.checkout!.isNotEmpty);

    final inTime = _checkedTimes[slot.id] ?? formatUtcToLocalTime(slot.checkin) ?? '';
    final outTime = _checkedOutTimes[slot.id] ?? formatUtcToLocalTime(slot.checkout) ?? '';

    final ampel = _slotAmpeln[slot.id] ?? '🟢';

    Color statusColor = isOut ? Colors.blueGrey : (isIn ? Colors.green : Colors.orange);
    String statusText = isOut ? '🏁 Abgeschlossen' : (isIn ? '🟢 Eingecheckt' : '⚪ Geplant / Wartend');

    final fmt = DateFormat('HH:mm');
    String? startStr, endStr;
    try {
      if (slot.dateStart != null) startStr = fmt.format(DateFormat('yyyy-MM-dd HH:mm:ss').parseUtc(slot.dateStart!).toLocal());
      if (slot.dateEnd != null) endStr = fmt.format(DateFormat('yyyy-MM-dd HH:mm:ss').parseUtc(slot.dateEnd!).toLocal());
    } catch (_) {}

    final isOtherEmployee = slot.angestellteId != null &&
        _currentAngestellteId != null &&
        slot.angestellteId != _currentAngestellteId;
    final showEmployeeHeader = _hasSupervisorCapabilities || isOtherEmployee;

    return Card(
      key: ValueKey(slot.id),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withOpacity(0.35), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Prominenter Mitarbeiter-Header (bei Supervisor/Admin/Team-Ansicht)
            if (showEmployeeHeader) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.06) : Colors.blue.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (isDark ? Colors.cyanAccent : AppConstants.primaryColor).withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: isDark ? Colors.blueGrey.shade800 : Colors.blue.shade100,
                      child: Icon(Icons.person, size: 14, color: isDark ? Colors.cyanAccent : AppConstants.primaryColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        slot.angestellteName != null && slot.angestellteName!.isNotEmpty
                            ? slot.angestellteName!
                            : 'Mitarbeiter noch nicht zugewiesen',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? Colors.white : AppConstants.primaryColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (slot.isEinsatzleiter(_currentAngestellteId))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Einsatzleitung',
                          style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
            ],

            // Status-Badge, Ordnernummer & Zeit
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                _buildOrdnerNummerChip(slot, isDark),
                const Spacer(),
                if (startStr != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '$startStr${endStr != null ? ' – $endStr' : ''} Uhr',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Schichtbezeichnung / Name
            Text(
              slot.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (slot.schichtbezeichnung != null && slot.schichtbezeichnung!.isNotEmpty && slot.schichtbezeichnung != slot.name)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  slot.schichtbezeichnung!,
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
                ),
              ),

            // Objekt & Einsatzort
            if (slot.objekteName != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.location_on, size: 15, color: isDark ? Colors.cyanAccent : AppConstants.primaryColor),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      slot.objekteName!,
                      style: TextStyle(
                        color: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // Check-in / Check-out Zeitstempel
            if (isIn || isOut) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    if (isIn) ...[
                      Text(ampel, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      Text('Check-In: $inTime Uhr', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    ],
                    if (isOut) ...[
                      const SizedBox(width: 16),
                      const Icon(Icons.logout, size: 14, color: Colors.blueGrey),
                      const SizedBox(width: 4),
                      Text('Check-Out: $outTime Uhr', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.blueGrey)),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            // 1-Tap Aktions-Buttons (mit Inline-Ladeindikator, um Scrollen stabil zu halten)
            Row(
              children: [
                if (!isIn && !isOut)
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: (!CheckinStateService().isGloballyEnabled && !_acl.isAdmin)
                          ? ElevatedButton.icon(
                              icon: const Icon(Icons.block, size: 20),
                              label: const Text(
                                'Check-In deaktiviert',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? Colors.white12 : Colors.grey.shade400,
                                foregroundColor: isDark ? Colors.white38 : Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: null,
                            )
                          : ElevatedButton.icon(
                              icon: isThisSlotProcessing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.login, size: 20),
                              label: Text(
                                isThisSlotProcessing ? 'Wird geprüft...' : 'Vor Ort Einchecken',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                foregroundColor: Colors.white,
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _isProcessing ? null : () => _doCheckIn(slot),
                            ),
                    ),
                  ),
                if (isIn && !isOut) ...[
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.check_circle, size: 18, color: Colors.green),
                        label: Text('Eingecheckt ($inTime)', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.green, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        icon: isThisSlotProcessing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.logout, size: 18),
                        label: Text(
                          isThisSlotProcessing ? 'Wird beendet...' : 'Auschecken',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isProcessing ? null : () => _doCheckOut(slot),
                      ),
                    ),
                  ),
                ],
                if (isOut)
                  Expanded(
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check, size: 18, color: Colors.grey.shade500),
                          const SizedBox(width: 6),
                          Text('Schicht vollständig abgeschlossen', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
