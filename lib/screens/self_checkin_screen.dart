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
import '../services/location_tracking_service.dart';
import '../widgets/alleinarbeit_consent_dialog.dart';
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

      relevantSlots.sort((a, b) {
        DateTime aStart = DateTime(1970);
        if (a.dateStart != null && a.dateStart!.isNotEmpty) {
          try {
            aStart = espoDateToLocal(a.dateStart!);
          } catch (_) {}
        }
        DateTime bStart = DateTime(1970);
        if (b.dateStart != null && b.dateStart!.isNotEmpty) {
          try {
            bStart = espoDateToLocal(b.dateStart!);
          } catch (_) {}
        }
        final cmp = aStart.compareTo(bStart);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });

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
        } else {
          _checkedIn.remove(s.id);
          _checkedTimes.remove(s.id);
          _slotAmpeln.remove(s.id);
        }
        if (s.checkout != null && s.checkout!.isNotEmpty) {
          _checkedOut.add(s.id);
          final localOut = formatUtcToLocalTime(s.checkout);
          if (localOut != null) {
            _checkedOutTimes[s.id] = localOut;
          }
        } else {
          _checkedOut.remove(s.id);
          _checkedOutTimes.remove(s.id);
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
    return _allRelevantSlots.any((s) => s.isEinsatzleiter(_currentAngestellteId) || (s.canEditOnr == true) || (s.isEinsatzleiterServer == true));
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

    if (_searchQuery.isNotEmpty) {
      baseList = baseList.where((s) {
        final nameMatch = s.name.toLowerCase().contains(_searchQuery);
        final objMatch = s.objekteName?.toLowerCase().contains(_searchQuery) ?? false;
        final empMatch = s.angestellteName?.toLowerCase().contains(_searchQuery) ?? false;
        final posMatch = s.positionsname?.toLowerCase().contains(_searchQuery) ?? false;
        final onrMatch = s.oNr?.toLowerCase().contains(_searchQuery) ?? false;
        return nameMatch || objMatch || empMatch || posMatch || onrMatch;
      }).toList();
    }

    // Sortierung wie in Schichten: Chronologisch nach Schichtbeginn (Beginnzeit)
    baseList.sort((a, b) {
      DateTime aStart = DateTime(1970);
      if (a.dateStart != null && a.dateStart!.isNotEmpty) {
        try {
          aStart = espoDateToLocal(a.dateStart!);
        } catch (_) {}
      }
      DateTime bStart = DateTime(1970);
      if (b.dateStart != null && b.dateStart!.isNotEmpty) {
        try {
          bStart = espoDateToLocal(b.dateStart!);
        } catch (_) {}
      }
      final cmp = aStart.compareTo(bStart);
      if (cmp != 0) return cmp;
      return a.name.compareTo(b.name);
    });

    return baseList;
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

    // DGUV V23 Alleinarbeiterschutz: Zustimmung vor dem Check-In einholen (STRIKT NUR für Nachtschichten mit Alleinarbeit)
    if (slot.requiresAlleinarbeitConsent) {
      final consentGiven = await showAlleinarbeitConsentDialog(context, slot);
      if (consentGiven != true) {
        if (mounted) {
          setState(() => _processingSlotId = null);
          _showErrorSnackbar('Check-In abgebrochen: Für Alleinarbeitsschichten ist die Zustimmung zum Schutz-Tracking gemäß DGUV V23 erforderlich.');
        }
        return;
      }

      // Revisionssichere Einwilligung an den Server senden
      final success = await _api.confirmAlleinarbeitConsent(slotId: slot.id);
      if (success) {
        slot.alleinarbeitConsentAt = DateTime.now().toUtc().toIso8601String();
      }
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

        // Live-Tracking für Alleinarbeit starten (STRIKT nur für Nachtschichten mit Alleinarbeit)
        if (slot.isAlleinarbeitNachtschicht) {
          LocationTrackingService().startTracking(
            slotId: slot.id,
            intervalMinutes: slot.alleinarbeitIntervallMinuten,
            objectName: slot.accountName ?? slot.objekteName,
          );
        }

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

  Future<int?> _showPauseSelectionDialog(Slot slot) async {
    int selectedPause = 0;
    int workedMinutes = 0;
    try {
      final checkinTimeStr = _checkedTimes[slot.id] ?? slot.checkin;
      if (checkinTimeStr != null && checkinTimeStr.isNotEmpty) {
        DateTime? inTime;
        if (checkinTimeStr.contains(':') && !checkinTimeStr.contains('T') && !checkinTimeStr.contains('-')) {
          final parts = checkinTimeStr.split(':');
          final now = DateTime.now();
          inTime = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
        } else {
          inTime = espoUtcToLocal(checkinTimeStr);
        }
        workedMinutes = DateTime.now().difference(inTime).inMinutes;
      }
    } catch (_) {}

    if (workedMinutes >= 540) {
      selectedPause = 45;
    } else if (workedMinutes >= 360) {
      selectedPause = 30;
    }

    final isOtherPerson = slot.angestellteName != null &&
        slot.angestellteId != null &&
        slot.angestellteId != _currentAngestellteId;

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        int tempPause = selectedPause;
        final customController = TextEditingController();
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              title: Row(
                children: [
                  const Icon(Icons.logout, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Text(
                    'Schicht auschecken',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOtherPerson
                        ? 'Schicht von „${slot.angestellteName}“ (${slot.name}) jetzt beenden.'
                        : 'Möchtest du die Schicht „${slot.name}“ jetzt beenden?',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Genommene Pause angeben:',
                    style: TextStyle(
                      color: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (workedMinutes >= 360) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade700.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.amber, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              workedMinutes >= 540
                                  ? 'ArbZG (>9h Schicht): mind. 45 Min gesetzliche Pause'
                                  : 'ArbZG (>6h Schicht): mind. 30 Min gesetzliche Pause',
                              style: const TextStyle(color: Colors.amber, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [0, 15, 30, 45, 60].map((mins) {
                      final isSelected = tempPause == mins && customController.text.isEmpty;
                      return ChoiceChip(
                        label: Text(
                          '$mins Min',
                          style: TextStyle(
                            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: AppConstants.primaryColor,
                        backgroundColor: isDark ? Colors.white10 : Colors.grey.shade100,
                        onSelected: (val) {
                          if (val) {
                            setModalState(() {
                              tempPause = mins;
                              customController.clear();
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: customController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Oder andere Minutenzahl eingeben...',
                      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400, fontSize: 12),
                      filled: true,
                      fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val);
                      if (parsed != null) {
                        setModalState(() => tempPause = parsed);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Abbrechen')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, tempPause),
                  style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryColor, foregroundColor: Colors.white),
                  child: const Text('Jetzt Auschecken'),
                ),
              ],
            );
          },
        );
      },
    );
    return result;
  }

  Future<void> _doCheckOut(Slot slot) async {
    if (_isProcessing) return;

    final pauseMinutes = await _showPauseSelectionDialog(slot);
    if (pauseMinutes == null) return;

    if (!mounted) return;
    setState(() => _processingSlotId = slot.id);

    // 1. GPS Geofence Check
    final gpsResult = await _location.checkGeofence(slot);
    if (!gpsResult.isSuccess) {
      if (mounted) setState(() => _processingSlotId = null);
      _showGpsErrorDialog(gpsResult, slot, isCheckIn: false);
      return;
    }

    final bool pauseIgnoriert = pauseMinutes == 0;
    await _executeCheckOut(slot, pauseMinutes: pauseMinutes, pausenregelungIgnoriert: pauseIgnoriert);
  }

  /// Führt den tatsächlichen Check-Out aus (nach GPS-Bestätigung oder Admin-Freigabe)
  Future<void> _executeCheckOut(
    Slot slot, {
    int? pauseMinutes,
    bool? pausenregelungIgnoriert,
  }) async {
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
        pauseMinutes: pauseMinutes,
        pausenregelungIgnoriert: pausenregelungIgnoriert,
      );

      final isOffline = res['offline'] == true;
      final timeStr = res['time'] as String? ?? nowHHMM;

      if (mounted) {
        setState(() {
          _checkedOut.add(slot.id);
          _checkedOutTimes[slot.id] = timeStr;
        });
        final targetName = slot.angestellteName != null ? ' (${slot.angestellteName})' : '';
        if (LocationTrackingService().activeSlotId == slot.id) {
          LocationTrackingService().stopTracking();
        }

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

  bool _hasOrdnerNummerChip(Slot slot) {
    final canEdit = slot.canUserEditOnr(_currentAngestellteId, isAdmin: _acl.isAdmin);
    final hasOnr = slot.oNr != null && slot.oNr!.trim().isNotEmpty;
    return hasOnr || canEdit;
  }

  /// Öffnet ein modales Sheet zur Mitarbeiterauswahl / Schichttausch / Springer-Eingabe
  Future<void> _showEmployeeSelectionSheet(Slot slot) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _EmployeeSelectionSheet(
          slot: slot,
          isDark: isDark,
          onEmployeeSelected: (empId, empName, {kpId, freierName, bewacherId, oNr}) async {
            Navigator.pop(sheetContext);
            await _assignEmployee(
              slot,
              empId,
              empName,
              kooperationspartnerId: kpId,
              freierMitarbeiterName: freierName,
              bewacherId: bewacherId,
              oNr: oNr,
            );
          },
          onRemoveAssignment: () async {
            Navigator.pop(sheetContext);
            await _assignEmployee(slot, null, null);
          },
        );
      },
    );
  }

  Future<void> _assignEmployee(
    Slot slot,
    String? angestellteId,
    String? angestellteName, {
    String? kooperationspartnerId,
    String? freierMitarbeiterName,
    String? bewacherId,
    String? oNr,
  }) async {
    try {
      final res = await _api.assignEmployeeToSlot(
        slotId: slot.id,
        angestellteId: angestellteId,
        kooperationspartnerId: kooperationspartnerId,
        freierMitarbeiterName: freierMitarbeiterName,
        bewacherId: bewacherId,
        oNr: oNr,
      );

      if (res['success'] == true) {
        if (!mounted) return;
        setState(() {
          final idx = _allRelevantSlots.indexWhere((s) => s.id == slot.id);
          if (idx != -1) {
            final isP = res['isPartner'] == true;
            final effectiveName = freierMitarbeiterName ?? angestellteName ?? (res['angestellteName'] as String?) ?? '';
            _allRelevantSlots[idx] = _allRelevantSlots[idx].copyWith(
              angestellteId: angestellteId,
              angestellteName: effectiveName,
              bewacherID: res['bewacherId']?.toString() ?? bewacherId ?? _allRelevantSlots[idx].bewacherID,
              ersatzNotiz: res['ersatzNotiz']?.toString() ?? _allRelevantSlots[idx].ersatzNotiz,
              isManualSpringer: freierMitarbeiterName != null && freierMitarbeiterName.isNotEmpty,
              oNr: res['oNr']?.toString() ?? oNr ?? _allRelevantSlots[idx].oNr,
              kooperationspartnerId: res['kooperationspartnerId'] ?? kooperationspartnerId ?? _allRelevantSlots[idx].kooperationspartnerId,
              kooperationspartnerName: res['kooperationspartnerName'] ?? _allRelevantSlots[idx].kooperationspartnerName,
              isPartner: res['isPartner'] != null ? isP : (kooperationspartnerId != null && kooperationspartnerId != '69e9f2a93910fbbbc' && kooperationspartnerId != '6a05b9091aed30701' && kooperationspartnerId != '__ALL__'),
              isIntern: res['isIntern'] != null ? !isP : (kooperationspartnerId == null || kooperationspartnerId == '69e9f2a93910fbbbc' || kooperationspartnerId == '6a05b9091aed30701'),
            );
          }
        });

        _showSuccessSnackbar(
          freierMitarbeiterName != null && freierMitarbeiterName.isNotEmpty
              ? '✅ Springer „$freierMitarbeiterName“ erfolgreich eingetragen'
              : (angestellteId != null
                  ? (slot.angestellteId != null && slot.angestellteId != angestellteId
                      ? '🔄 Vor-Ort-Austausch: $angestellteName zugewiesen'
                      : '✅ $angestellteName erfolgreich zugewiesen')
                  : '✅ Mitarbeiter-Zuweisung entfernt'),
        );

        // Hintergrund-Aktualisierung
        _loadTodaysSlots(silent: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackbar('❌ Fehler bei der Zuweisung: $e');
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

          // Live Headcount Banner für Einsatzleiter / Admin
          if (_hasSupervisorCapabilities && displayedList.isNotEmpty)
            _buildLiveHeadcountBanner(displayedList, isDark),

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

  Widget _buildLiveHeadcountBanner(List<Slot> slots, bool isDark) {
    int total = slots.length;
    int checkedInCount = 0;
    int waitingCount = 0;
    int completedCount = 0;
    int internCount = 0;
    int partnerCount = 0;

    for (final s in slots) {
      final isIn = _checkedIn.contains(s.id) || (s.checkin != null && s.checkin!.isNotEmpty);
      final isOut = _checkedOut.contains(s.id) || (s.checkout != null && s.checkout!.isNotEmpty);

      if (isOut) {
        completedCount++;
      } else if (isIn) {
        checkedInCount++;
      } else {
        waitingCount++;
      }

      if (s.isExternalPartner) {
        partnerCount++;
      } else {
        internCount++;
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, size: 18, color: isDark ? Colors.cyanAccent : AppConstants.primaryColor),
              const SizedBox(width: 8),
              Text(
                'Live-Kopfzähler vor Ort',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.cyanAccent : AppConstants.primaryColor).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Gesamt: $total',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildHeadcountPill('🟢 Anwesend', '$checkedInCount', Colors.green, isDark),
              const SizedBox(width: 8),
              _buildHeadcountPill('⚪ Offen', '$waitingCount', Colors.orange, isDark),
              const SizedBox(width: 8),
              _buildHeadcountPill('🏁 Beendet', '$completedCount', Colors.blueGrey, isDark),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🏢 Intern: $internCount',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
              Text(
                '🤝 Partner: $partnerCount',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeadcountPill(String label, String count, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.15 : 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              count,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.grey.shade800),
            ),
          ],
        ),
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

  /// Zeigt ein informatives Dialog-Popup mit allen ungekürzten Mitarbeiterdetails
  Future<void> _showEmployeeDetailsDialog(Slot slot) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final empName = slot.angestellteName?.trim();
    final hasEmp = empName != null && empName.isNotEmpty;
    final firmaName = slot.kooperationspartnerName?.trim();
    final bewacherId = slot.bewacherID?.trim();
    final onr = slot.oNr?.trim() ?? slot.empDefaultOnr?.trim();
    final pos = slot.positionsname?.trim() ?? slot.schichtbezeichnung?.trim();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: isDark ? Colors.cyanAccent.withOpacity(0.15) : AppConstants.primaryColor.withOpacity(0.12),
              child: Icon(
                Icons.badge_rounded,
                size: 20,
                color: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bewacher-Informationen',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1),
              const SizedBox(height: 14),
              if (slot.originalGeplantName != null && slot.originalGeplantName != slot.effectiveEmployeeName) ...[
                _buildDetailInfoRow(
                  icon: Icons.person_off_outlined,
                  label: 'Ursprünglich geplant',
                  value: slot.originalGeplantName!,
                  isDark: isDark,
                  highlightColor: Colors.grey.shade500,
                ),
                const SizedBox(height: 10),
              ],
              _buildDetailInfoRow(
                icon: Icons.person_rounded,
                label: 'Name',
                value: hasEmp ? empName : 'Noch nicht zugewiesen',
                isBold: true,
                isDark: isDark,
                highlightColor: isDark ? Colors.white : Colors.black87,
              ),
              const SizedBox(height: 10),
              _buildDetailInfoRow(
                icon: Icons.business_rounded,
                label: 'Firma / Arbeitgeber',
                value: (firmaName != null && firmaName.isNotEmpty)
                    ? firmaName
                    : (slot.isInternalEmployee ? 'MB-SCC GmbH' : 'Keine Angabe'),
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _buildDetailInfoRow(
                icon: Icons.fingerprint_rounded,
                label: 'Bewacher-ID',
                value: (bewacherId != null && bewacherId.isNotEmpty) ? bewacherId : 'Keine hinterlegt',
                isMonospace: true,
                isDark: isDark,
                highlightColor: isDark ? Colors.cyanAccent : Colors.teal.shade800,
              ),
              const SizedBox(height: 10),
              _buildDetailInfoRow(
                icon: Icons.folder_shared_outlined,
                label: 'Ordnernummer',
                value: (onr != null && onr.isNotEmpty) ? '#$onr' : 'Keine zugewiesen',
                isDark: isDark,
              ),
              if (pos != null && pos.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildDetailInfoRow(
                  icon: Icons.pin_drop_outlined,
                  label: 'Position',
                  value: pos,
                  isDark: isDark,
                  highlightColor: isDark ? Colors.amberAccent : Colors.amber.shade900,
                ),
              ],
              if (slot.objekteName != null && slot.objekteName!.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildDetailInfoRow(
                  icon: Icons.place_outlined,
                  label: 'Objekt',
                  value: slot.objekteName!,
                  isDark: isDark,
                ),
              ],
              if (slot.isSpringer) ...[
                const SizedBox(height: 10),
                _buildDetailInfoRow(
                  icon: Icons.swap_calls_rounded,
                  label: 'Status',
                  value: 'Springer / Vor-Ort-Ersatz',
                  isDark: isDark,
                  highlightColor: Colors.amber,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
            ),
            child: const Text('Schließen', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isBold = false,
    bool isMonospace = false,
    Color? highlightColor,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: isDark ? Colors.white60 : Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              fontFamily: isMonospace ? 'monospace' : null,
              color: highlightColor ?? (isDark ? Colors.white : Colors.black87),
            ),
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
    String statusText = isOut ? '🏁 Abgeschlossen' : (isIn ? '🟢 Eingecheckt' : '⚪ Geplant');

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
    final canAssignEmployee = _acl.isAdmin ||
        _hasSupervisorCapabilities ||
        (slot.canEditOnr == true) ||
        (slot.isEinsatzleiterServer == true);
    final hasAssignedEmployee = slot.angestellteName != null && slot.angestellteName!.trim().isNotEmpty;

    // Positionsangabe prüfen
    final hasPositionsname = slot.positionsname != null && slot.positionsname!.trim().isNotEmpty;
    final hasSchichtbez = slot.schichtbezeichnung != null && slot.schichtbezeichnung!.trim().isNotEmpty && slot.schichtbezeichnung != slot.name;
    final posText = hasPositionsname ? slot.positionsname!.trim() : (hasSchichtbez ? slot.schichtbezeichnung!.trim() : null);

    return Card(
      key: ValueKey(slot.id),
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.35), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Kompakte einzeilige Top-Bar: Status-Badge, Ordner-Chip & Schicht-Uhrzeit
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_hasOrdnerNummerChip(slot)) ...[
                  const SizedBox(width: 6),
                  _buildOrdnerNummerChip(slot, isDark),
                ],
                const Spacer(),
                if (startStr != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule, size: 13, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '$startStr${endStr != null ? ' – $endStr' : ''} Uhr',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // 2. Mitarbeiter-Header (bei Supervisor/Admin/Team-Ansicht)
            if (showEmployeeHeader) ...[
              if (!hasAssignedEmployee)
                if (canAssignEmployee)
                  InkWell(
                    onTap: () => _showEmployeeSelectionSheet(slot),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.amber.shade900.withOpacity(0.18) : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.amber.shade400.withOpacity(0.7) : Colors.amber.shade700,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: isDark ? Colors.amber.shade800 : Colors.amber.shade100,
                            child: Icon(Icons.person_add_alt_1, size: 14, color: isDark ? Colors.amberAccent : Colors.amber.shade900),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mitarbeiter auswählen',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? Colors.amberAccent : Colors.amber.shade900,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.amber.shade700 : Colors.amber.shade600,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.search, size: 13, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.3),
                      ),
                    ),
                    child: const Row(
                      children: [
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.grey,
                          child: Icon(Icons.person_outline, size: 13, color: Colors.white),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Mitarbeiter noch nicht zugewiesen',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
              else
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (isDark ? Colors.cyanAccent : AppConstants.primaryColor).withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Klickbares Personen-Symbol: Öffnet Popup mit vollständigen ungekürzten Infos
                      InkWell(
                        onTap: () => _showEmployeeDetailsDialog(slot),
                        borderRadius: BorderRadius.circular(16),
                        child: Tooltip(
                          message: 'Mitarbeiter-Details anzeigen',
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 13,
                                backgroundColor: isDark ? Colors.blueGrey.shade800 : Colors.blue.shade100,
                                child: Icon(Icons.person, size: 16, color: isDark ? Colors.cyanAccent : AppConstants.primaryColor),
                              ),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(1.5),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.info_outline,
                                    size: 9,
                                    color: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (slot.originalGeplantName != null && slot.originalGeplantName != slot.angestellteName)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 1),
                                child: Text(
                                  'Geplant: ${slot.originalGeplantName!}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.grey.shade500,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    slot.angestellteName!,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                      color: isDark ? Colors.white : AppConstants.primaryColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (slot.isSpringer) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.amber.shade700, width: 0.8),
                                    ),
                                    child: const Text(
                                      'SPRINGER',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.amber,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (slot.kooperationspartnerName != null && slot.kooperationspartnerName!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Text(
                                  'Firma: ${slot.kooperationspartnerName}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Tauschen-Button: Als reines Symbol ohne ausgeschriebenes Wort
                      if (canAssignEmployee) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                          tooltip: 'Schicht tauschen / neu zuweisen',
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(5),
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          style: IconButton.styleFrom(
                            backgroundColor: (isDark ? Colors.cyanAccent : AppConstants.primaryColor).withOpacity(0.12),
                            foregroundColor: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                              side: BorderSide(
                                color: (isDark ? Colors.cyanAccent : AppConstants.primaryColor).withOpacity(0.3),
                              ),
                            ),
                          ),
                          onPressed: () => _showEmployeeSelectionSheet(slot),
                        ),
                      ],
                    ],
                  ),
                ),
            ],

            // 3. Schichttitel & Positionsangabe
            Text(
              slot.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            if (posText != null) ...[
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.indigo.shade50.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? Colors.cyanAccent.withOpacity(0.35) : AppConstants.primaryColor.withOpacity(0.35),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.pin_drop_rounded,
                      size: 13,
                      color: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Position: ',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        posText,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (hasPositionsname && hasSchichtbez)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  slot.schichtbezeichnung!,
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 11.5),
                ),
              ),

            // 4. Objekt & Einsatzort (kompakt)
            if (slot.objekteName != null) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(Icons.location_on, size: 14, color: isDark ? Colors.cyanAccent : AppConstants.primaryColor),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      slot.objekteName!,
                      style: TextStyle(
                        color: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.cyanAccent : AppConstants.primaryColor).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: (isDark ? Colors.cyanAccent : AppConstants.primaryColor).withOpacity(0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.radar_rounded,
                          size: 10,
                          color: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${slot.geofenceRadius ?? slot.rad ?? 50}m',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            // 5. Check-in / Check-out Zeitstempel
            if (isIn || isOut) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    if (isIn) ...[
                      Text(ampel, style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 5),
                      Text('Check-In: $inTime Uhr', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5)),
                    ],
                    if (isOut) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.logout, size: 13, color: Colors.blueGrey),
                      const SizedBox(width: 4),
                      Text('Check-Out: $outTime Uhr', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5, color: Colors.blueGrey)),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // 6. 1-Tap Aktions-Buttons
            Row(
              children: [
                if (!isIn && !isOut)
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: (!CheckinStateService().isGloballyEnabled && !_acl.isAdmin)
                          ? ElevatedButton.icon(
                              icon: const Icon(Icons.block, size: 18),
                              label: const Text(
                                'Check-In deaktiviert',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? Colors.white12 : Colors.grey.shade400,
                                foregroundColor: isDark ? Colors.white38 : Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: null,
                            )
                          : ElevatedButton.icon(
                              icon: isThisSlotProcessing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.login, size: 18),
                              label: Text(
                                isThisSlotProcessing ? 'Wird geprüft...' : 'Vor Ort Einchecken',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                foregroundColor: Colors.white,
                                elevation: 1.5,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _isProcessing ? null : () => _doCheckIn(slot),
                            ),
                    ),
                  ),
                if (isIn && !isOut) ...[
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.check_circle, size: 16, color: Colors.green),
                        label: Text('Eingecheckt ($inTime)', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11.5)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.green, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        icon: isThisSlotProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.logout, size: 16),
                        label: Text(
                          isThisSlotProcessing ? 'Wird beendet...' : 'Auschecken',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          elevation: 1.5,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isProcessing ? null : () => _doCheckOut(slot),
                      ),
                    ),
                  ),
                ],
                if (isOut)
                  Expanded(
                    child: Container(
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check, size: 16, color: Colors.grey.shade500),
                          const SizedBox(width: 6),
                          Text('Schicht vollständig abgeschlossen', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600, fontSize: 12)),
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

class _EmployeeSelectionSheet extends StatefulWidget {
  final Slot slot;
  final bool isDark;
  final Function(String? empId, String empName, {String? kpId, String? freierName, String? bewacherId, String? oNr}) onEmployeeSelected;
  final VoidCallback onRemoveAssignment;

  const _EmployeeSelectionSheet({
    required this.slot,
    required this.isDark,
    required this.onEmployeeSelected,
    required this.onRemoveAssignment,
  });

  @override
  State<_EmployeeSelectionSheet> createState() => _EmployeeSelectionSheetState();
}

class _EmployeeSelectionSheetState extends State<_EmployeeSelectionSheet> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();

  // Tab: 0 = Aus Liste wählen, 1 = Freier Name / Springer
  int _currentTab = 0;

  // Controller für Springer
  final _springerFormKey = GlobalKey<FormState>();
  final _freierNameCtrl = TextEditingController();
  final _bewacherIdCtrl = TextEditingController();
  final _oNrCtrl = TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _allEmployees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  List<Map<String, dynamic>> _partners = [];
  String? _selectedKpId;
  String? _kpName;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    final initialKpId = widget.slot.kooperationspartnerId;
    if (initialKpId == null || initialKpId.isEmpty || initialKpId == '69e9f2a93910fbbbc' || initialKpId == '6a05b9091aed30701') {
      _selectedKpId = '69e9f2a93910fbbbc';
      _kpName = 'MB Security Concept & Consulting GmbH';
    } else {
      _selectedKpId = initialKpId;
      _kpName = widget.slot.kooperationspartnerName;
    }

    if (widget.slot.oNr != null && widget.slot.oNr!.isNotEmpty) {
      _oNrCtrl.text = widget.slot.oNr!;
    }
    if (widget.slot.bewacherID != null && widget.slot.bewacherID!.isNotEmpty) {
      _bewacherIdCtrl.text = widget.slot.bewacherID!;
    }

    _loadPartners();
    _fetchEmployees();
  }

  String? _getEffectiveKpValue() {
    if (_selectedKpId == '__ALL__') return '__ALL__';
    if (_selectedKpId == null || _selectedKpId == '69e9f2a93910fbbbc' || _selectedKpId == '6a05b9091aed30701') {
      return '69e9f2a93910fbbbc';
    }
    if (_partners.any((p) => p['id'] == _selectedKpId)) {
      return _selectedKpId;
    }
    return '__ALL__';
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    _freierNameCtrl.dispose();
    _bewacherIdCtrl.dispose();
    _oNrCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPartners() async {
    try {
      final partners = await _api.getKooperationspartner();
      partners.sort((a, b) => ((a['name'] as String?) ?? '').toLowerCase().compareTo(((b['name'] as String?) ?? '').toLowerCase()));
      if (mounted) {
        setState(() {
          _partners = partners;
        });
      }
    } catch (e) {
      debugPrint('Error loading partners: $e');
    }
  }

  Future<void> _fetchEmployees({String? search}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _api.getAssignableEmployees(
        slotId: widget.slot.id,
        search: search,
        kooperationspartnerId: _selectedKpId,
      );

      final list = (res['list'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
      // Alphabetisch nach Name sortieren
      list.sort((a, b) {
        final aName = (a['name'] as String? ?? '').toLowerCase();
        final bName = (b['name'] as String? ?? '').toLowerCase();
        return aName.compareTo(bName);
      });

      final kpName = res['kooperationspartnerName'] as String?;

      if (!mounted) return;
      setState(() {
        _allEmployees = list;
        _filteredEmployees = list;
        if (kpName != null && kpName.isNotEmpty) {
          _kpName = kpName;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Fehler beim Laden: $e';
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    final q = query.trim().toLowerCase();
    _debounceTimer?.cancel();

    if (q.isEmpty) {
      setState(() => _filteredEmployees = _allEmployees);
      return;
    }

    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    // 1. Sofortige client-seitige Filterung für unmittelbare UI-Reaktion
    setState(() {
      _filteredEmployees = _allEmployees.where((emp) {
        final name = (emp['name'] ?? '').toString().toLowerCase();
        final pNr = (emp['personalnummer'] ?? '').toString().toLowerCase();
        final oNr = (emp['oNr'] ?? '').toString().toLowerCase();
        final quals = (emp['qualifikationen'] as List? ?? []).join(' ').toLowerCase();
        final kp = (emp['kooperationspartnerName'] ?? '').toString().toLowerCase();
        return words.every((word) =>
            name.contains(word) || pNr.contains(word) || oNr.contains(word) || quals.contains(word) || kp.contains(word));
      }).toList();
    });

    // 2. Debounced Server-Suche für firmenübergreifende Ergebnisse / Springer aus MB-SCC
    if (q.length >= 2) {
      _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
        try {
          final res = await _api.getAssignableEmployees(
            slotId: widget.slot.id,
            search: query.trim(),
            kooperationspartnerId: _selectedKpId,
          );
          final serverList = (res['list'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
          if (!mounted || _searchCtrl.text.trim() != query.trim()) return;

          setState(() {
            final existingIds = _filteredEmployees.map((e) => e['id']?.toString()).toSet();
            final combined = List<Map<String, dynamic>>.from(_filteredEmployees);
            for (final item in serverList) {
              final id = item['id']?.toString();
              if (id != null && !existingIds.contains(id)) {
                combined.add(item);
                existingIds.add(id);
              }
            }
            _filteredEmployees = combined;
          });
        } catch (e) {
          debugPrint('Debounced employee search error: $e');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isDark = widget.isDark;
    final hasCurrentEmployee = (widget.slot.angestellteId != null && widget.slot.angestellteId!.isNotEmpty) ||
        (widget.slot.angestellteName != null && widget.slot.angestellteName!.trim().isNotEmpty);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header: Titel & Schließen-Button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.cyanAccent : AppConstants.primaryColor).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.person_search_rounded,
                  color: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mitarbeiter zuweisen / Tauschen',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Firma: ${_kpName ?? widget.slot.kooperationspartnerName ?? 'MB-SCC (Intern)'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tab-Umschalter: [ 👥 Aus Liste wählen ] | [ ✍️ Freier Name / Springer ]
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _currentTab = 0),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _currentTab == 0
                            ? (isDark ? Colors.cyanAccent.withOpacity(0.2) : Colors.white)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _currentTab == 0
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '👥 Aus Liste wählen',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _currentTab == 0 ? FontWeight.bold : FontWeight.w500,
                            color: _currentTab == 0
                                ? (isDark ? Colors.cyanAccent : AppConstants.primaryColor)
                                : (isDark ? Colors.white60 : Colors.grey.shade700),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _currentTab = 1),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _currentTab == 1
                            ? (isDark ? Colors.amber.withOpacity(0.25) : Colors.white)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _currentTab == 1
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '✍️ Freier Name / Springer',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _currentTab == 1 ? FontWeight.bold : FontWeight.w500,
                            color: _currentTab == 1
                                ? Colors.amber
                                : (isDark ? Colors.white60 : Colors.grey.shade700),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // TAB-INHALTE
          if (_currentTab == 0) ...[
            // Kooperationspartner Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _getEffectiveKpValue(),
                  isExpanded: true,
                  dropdownColor: isDark ? const Color(0xFF1E222B) : Colors.white,
                  hint: const Text('Alle Firmen / Intern (MB-SCC)'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: '__ALL__',
                      child: Text('🌐 Alle Firmen / Firmenübergreifend', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    const DropdownMenuItem<String?>(
                      value: '69e9f2a93910fbbbc',
                      child: Text('🏢 MB-SCC (Intern)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    ..._partners
                        .where((p) => p['id'] != '69e9f2a93910fbbbc' && p['id'] != '6a05b9091aed30701')
                        .map((p) => DropdownMenuItem<String?>(
                              value: p['id'] as String?,
                              child: Text(
                                '🤝 ${p['name'] as String? ?? 'Unbekannter Partner'}',
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                  ],
                  onChanged: (newKpId) {
                    setState(() {
                      _selectedKpId = newKpId;
                      if (newKpId == '__ALL__') {
                        _kpName = 'Alle Firmen';
                      } else if (newKpId == '69e9f2a93910fbbbc' || newKpId == null) {
                        _kpName = 'MB-SCC (Intern)';
                      } else {
                        final found = _partners.firstWhere((p) => p['id'] == newKpId, orElse: () => {});
                        _kpName = found['name'] as String?;
                      }
                    });
                    _fetchEmployees(search: _searchCtrl.text.trim());
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Suchleiste mit Live-Suche
            TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Nach Name, Personal-Nr. oder Ordner-Nr. suchen...',
                hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.cyanAccent : AppConstants.primaryColor, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Treffer-Anzahl & Schicht-Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isLoading
                        ? 'Lade Mitarbeiter...'
                        : '${_filteredEmployees.length} Mitarbeiter verfügbar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                  if (hasCurrentEmployee)
                    InkWell(
                      onTap: widget.onRemoveAssignment,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.person_remove_outlined, size: 13, color: Colors.red.shade400),
                            const SizedBox(width: 4),
                            Text(
                              'Zuweisung aufheben',
                              style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 12),

            // Liste der Mitarbeiter
            Expanded(
              child: _buildListContent(isDark),
            ),
          ] else ...[
            // Tab 1: Freier Name / Springer Formular
            Expanded(
              child: _buildSpringerForm(isDark, hasCurrentEmployee),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpringerForm(bool isDark, bool hasCurrentEmployee) {
    return SingleChildScrollView(
      child: Form(
        key: _springerFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            // Info Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Für externe Aushilfen, Springer oder Partner-Personal ohne hinterlegtes Profil. Name und Bewacher-ID werden auf der Schicht und im Wachbuch dokumentiert.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Firma / Kooperationspartner Dropdown
            Text(
              'Firma / Arbeitgeber',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _getEffectiveKpValue() == '__ALL__' ? '69e9f2a93910fbbbc' : _getEffectiveKpValue(),
                  isExpanded: true,
                  dropdownColor: isDark ? const Color(0xFF1E222B) : Colors.white,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: '69e9f2a93910fbbbc',
                      child: Text('🏢 MB-SCC (Intern)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    ..._partners
                        .where((p) => p['id'] != '69e9f2a93910fbbbc' && p['id'] != '6a05b9091aed30701')
                        .map((p) => DropdownMenuItem<String?>(
                              value: p['id'] as String?,
                              child: Text(
                                '🤝 ${p['name'] as String? ?? 'Unbekannter Partner'}',
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                  ],
                  onChanged: (newKpId) {
                    setState(() {
                      _selectedKpId = newKpId;
                      if (newKpId == '69e9f2a93910fbbbc' || newKpId == null) {
                        _kpName = 'MB-SCC (Intern)';
                      } else {
                        final found = _partners.firstWhere((p) => p['id'] == newKpId, orElse: () => {});
                        _kpName = found['name'] as String?;
                      }
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Vor- und Nachname (Pflicht)
            Text(
              'Vor- und Nachname des Springers *',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _freierNameCtrl,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'z. B. Max Mustermann',
                hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey.shade500),
                prefixIcon: const Icon(Icons.person_add_rounded, size: 20),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.amber, width: 1.5),
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Bitte Vor- und Nachnamen eingeben' : null,
            ),
            const SizedBox(height: 14),

            // Bewacher-ID (BWR-Nummer)
            Text(
              'Bewacher-ID / Bewachungsregister-Nr.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _bewacherIdCtrl,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'z. B. B-12345678 (BWR-ID)',
                hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey.shade500),
                prefixIcon: const Icon(Icons.badge_rounded, size: 20),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.amber, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Ordner-Nr. (O-NR)
            Text(
              'Ordner-Nummer (O-NR)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _oNrCtrl,
              keyboardType: TextInputType.text,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'z. B. 042 (optional)',
                hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey.shade500),
                prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.amber, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Zuweisen-Button
            ElevatedButton.icon(
              onPressed: () {
                if (_springerFormKey.currentState?.validate() ?? false) {
                  final name = _freierNameCtrl.text.trim();
                  final bId = _bewacherIdCtrl.text.trim();
                  final onr = _oNrCtrl.text.trim();
                  final kpId = (_selectedKpId == '__ALL__' || _selectedKpId == null)
                      ? '69e9f2a93910fbbbc'
                      : _selectedKpId;

                  widget.onEmployeeSelected(
                    null,
                    name,
                    kpId: kpId,
                    freierName: name,
                    bewacherId: bId.isNotEmpty ? bId : null,
                    oNr: onr.isNotEmpty ? onr : null,
                  );
                }
              },
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text(
                'Schicht Springer zuweisen',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 3,
                shadowColor: const Color(0xFF10B981).withOpacity(0.5),
              ),
            ),
            if (hasCurrentEmployee) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: widget.onRemoveAssignment,
                icon: Icon(Icons.person_remove_outlined, size: 16, color: Colors.red.shade400),
                label: Text(
                  'Aktuelle Zuweisung aufheben',
                  style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade400.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildListContent(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 36, color: Colors.red.shade400),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _fetchEmployees(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Erneut versuchen'),
            ),
          ],
        ),
      );
    }

    if (_filteredEmployees.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, size: 40, color: isDark ? Colors.white24 : Colors.grey.shade400),
            const SizedBox(height: 10),
            Text(
              _searchCtrl.text.isNotEmpty
                  ? 'Kein Mitarbeiter für „${_searchCtrl.text}“ gefunden'
                  : 'Keine aktiven Mitarbeiter für diese Partnerfirma gefunden',
              style: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade600, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _filteredEmployees.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
      itemBuilder: (context, idx) {
        final emp = _filteredEmployees[idx];
        final empId = emp['id'] as String? ?? '';
        final empName = emp['name'] as String? ?? '';
        final pNr = emp['personalnummer'] as String?;
        final oNr = emp['oNr'] as String?;
        final quals = emp['qualifikationen'] as List? ?? [];
        final isCurrentlyAssigned = widget.slot.angestellteId == empId;

        final initials = empName.trim().isNotEmpty
            ? empName.trim().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase()
            : '?';

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: isCurrentlyAssigned
                ? Colors.green.shade700
                : (isDark ? Colors.blueGrey.shade800 : Colors.blue.shade100),
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isCurrentlyAssigned ? Colors.white : (isDark ? Colors.cyanAccent : AppConstants.primaryColor),
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  empName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isCurrentlyAssigned
                        ? (isDark ? Colors.greenAccent : Colors.green.shade800)
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
              ),
              if (isCurrentlyAssigned)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 11, color: Colors.green),
                      SizedBox(width: 3),
                      Text('Zugewiesen', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (pNr != null && pNr.isNotEmpty)
                  _buildTag('P-Nr. #$pNr', isDark, Colors.blueGrey),
                if (oNr != null && oNr.isNotEmpty)
                  _buildTag('Ordner #$oNr', isDark, Colors.purple),
                if (emp['kooperationspartnerName'] != null && emp['kooperationspartnerName'].toString().isNotEmpty)
                  _buildTag(emp['kooperationspartnerName'].toString(), isDark, Colors.blue),
                ...quals.map((q) => _buildTag(q.toString(), isDark, Colors.teal)),
              ],
            ),
          ),
          trailing: isCurrentlyAssigned
              ? null
              : Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: isDark ? Colors.white38 : Colors.grey.shade400,
                ),
          onTap: isCurrentlyAssigned ? null : () {
            final chosenKpId = (emp['kooperationspartnerId'] as String?) ?? (_selectedKpId == '__ALL__' ? null : _selectedKpId);
            widget.onEmployeeSelected(empId, empName, kpId: chosenKpId);
          },
        );
      },
    );
  }

  Widget _buildTag(String text, bool isDark, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? color.shade900.withOpacity(0.3) : color.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? color.shade700.withOpacity(0.4) : color.shade300,
          width: 0.8,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isDark ? color.shade200 : color.shade800,
        ),
      ),
    );
  }
}
