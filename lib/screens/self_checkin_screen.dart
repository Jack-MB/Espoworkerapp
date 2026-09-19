import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/slot.dart';
import '../services/api_service.dart';
import '../services/acl_service.dart';
import '../services/secure_storage_service.dart';
import '../services/location_service.dart';
import '../services/sync_queue_service.dart';
import '../core/constants.dart';

/// Self-Service Check-In Screen für Mitarbeiter — inspiriert vom stationären Check-in-Terminal.
/// Da der Mitarbeiter in der App bereits authentifiziert ist, wird KEIN Barcode-Scanner benötigt.
/// Der Mitarbeiter sieht direkt seine Schichten für heute und kann mit 1-Tap ein- und auschecken.
class SelfCheckinScreen extends StatefulWidget {
  const SelfCheckinScreen({Key? key}) : super(key: key);

  @override
  State<SelfCheckinScreen> createState() => _SelfCheckinScreenState();
}

class _SelfCheckinScreenState extends State<SelfCheckinScreen> {
  final ApiService _api = ApiService();
  final AclService _acl = AclService();
  final LocationService _location = LocationService();
  final SyncQueueService _syncQueue = SyncQueueService();
  final SecureStorageService _storage = SecureStorageService();

  List<Slot> _slots = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentAngestellteId;

  // Lokaler Check-In-Status (gespeichert für nahtlosen Offline- und Online-Betrieb)
  Set<String> _checkedIn = {};
  Set<String> _checkedOut = {};
  Map<String, String> _checkedTimes = {};
  Map<String, String> _checkedOutTimes = {};
  Map<String, String> _slotAmpeln = {}; // cI Ampel (🟢 🟡 🔴)

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _acl.refresh();
    _initAndLoad();
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
      if (inJson != null) _checkedTimes = Map<String, String>.from(json.decode(inJson));
      if (outJson != null) _checkedOutTimes = Map<String, String>.from(json.decode(outJson));
    });
  }

  Future<void> _saveLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('admin_checked_slots', _checkedIn.toList());
    await prefs.setStringList('admin_checked_out_slots', _checkedOut.toList());
    await prefs.setString('admin_checked_times', json.encode(_checkedTimes));
    await prefs.setString('admin_checked_out_times', json.encode(_checkedOutTimes));
  }

  Future<void> _loadTodaysSlots() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      // Puffer für Nachtschichten: Gestern Mittag bis morgen Mittag
      final allSlots = await _api.getSlots(
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 1)),
      );

      // 1. Schichten filtern: Gehören zum aktuellen Mitarbeiter (oder alle bei Admin)
      final relevantSlots = allSlots.where((s) {
        if (!_acl.isAdmin && _currentAngestellteId != null) {
          if (s.angestellteId != null && s.angestellteId != _currentAngestellteId) {
            return false;
          }
        }

        if (s.dateStart == null) return false;
        final startPart = s.dateStart!.split(' ')[0];
        final endPart = s.dateEnd?.split(' ')[0] ?? startPart;

        // Schicht startet heute ODER lief über Mitternacht und endet heute
        return startPart == todayStr ||
            (startPart.compareTo(todayStr) <= 0 && endPart.compareTo(todayStr) >= 0);
      }).toList();

      relevantSlots.sort((a, b) => (a.dateStart ?? '').compareTo(b.dateStart ?? ''));

      // Backend-Werte in lokale Ampel-Map übernehmen
      for (final s in relevantSlots) {
        if (s.checkin != null && s.checkin!.isNotEmpty) {
          _checkedIn.add(s.id);
          if (!_checkedTimes.containsKey(s.id)) {
            _checkedTimes[s.id] = s.checkin!.contains(' ')
                ? s.checkin!.split(' ')[1].substring(0, 5)
                : s.checkin!.substring(0, 5);
          }
        }
        if (s.checkout != null && s.checkout!.isNotEmpty) {
          _checkedOut.add(s.id);
          if (!_checkedOutTimes.containsKey(s.id)) {
            _checkedOutTimes[s.id] = s.checkout!.contains(' ')
                ? s.checkout!.split(' ')[1].substring(0, 5)
                : s.checkout!.substring(0, 5);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _slots = relevantSlots;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Fehler beim Laden: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _doCheckIn(Slot slot) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // 1. GPS Geofence Check über zentralen LocationService
    final gpsResult = await _location.checkGeofence(slot);
    if (!gpsResult.isSuccess) {
      if (mounted) setState(() => _isProcessing = false);
      _showGpsErrorDialog(gpsResult, slot);
      return;
    }

    // 2. Zeitstempel berechnen
    final now = DateTime.now();
    final nowHHMM = DateFormat('HH:mm').format(now);
    final nowUtc = now.toUtc();
    final nowUtcStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(nowUtc);

    // Haptisches Feedback wie am Terminal
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

    // 3. API-Aufruf oder Offline-Queue
    try {
      await _api.checkInSlot(slot.id, checkInTime: nowUtcStr);
      if (mounted) {
        setState(() {
          _checkedIn.add(slot.id);
          _checkedTimes[slot.id] = nowHHMM;
          _slotAmpeln[slot.id] = ampel;
        });
        _showSuccessSnackbar('✅ Eingecheckt um $nowHHMM Uhr ($ampel)');
      }
    } catch (e) {
      // Offline-Fallback über SyncQueue
      debugPrint('SelfCheckin: Netzwerkfehler bei checkInSlot, reihe in SyncQueue ein: $e');
      final offlinePayload = {
        'checkin': nowUtcStr,
        'cI': ampel,
        'status': 'Durchgeführt',
      };
      await _syncQueue.enqueue(
        slotId: slot.id,
        data: offlinePayload,
        description: 'Check-In ${slot.name} ($nowHHMM)',
      );

      if (mounted) {
        setState(() {
          _checkedIn.add(slot.id);
          _checkedTimes[slot.id] = nowHHMM;
          _slotAmpeln[slot.id] = ampel;
        });
        _showSuccessSnackbar('✅ Vor Ort eingecheckt! (Offline gespeichert – wird bei Netz automatisch synchronisiert)');
      }
    }

    await _saveLocalState();
    if (mounted) setState(() => _isProcessing = false);
  }

  Future<void> _doCheckOut(Slot slot) async {
    if (_isProcessing) return;

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
        content: Text('Möchtest du dich jetzt von der Schicht „${slot.name}“ auschecken?'),
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
    setState(() => _isProcessing = true);

    // 1. GPS Geofence Check
    final gpsResult = await _location.checkGeofence(slot);
    if (!gpsResult.isSuccess) {
      if (mounted) setState(() => _isProcessing = false);
      _showGpsErrorDialog(gpsResult, slot);
      return;
    }

    // 2. Zeitstempel & Nachtschicht-Handling
    final now = DateTime.now();
    final nowHHMM = DateFormat('HH:mm').format(now);
    final nowUtc = now.toUtc();
    final nowUtcStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(nowUtc);

    HapticFeedback.heavyImpact();

    // 3. API-Aufruf oder Offline-Queue
    try {
      await _api.checkOutSlot(slot.id, checkOutTime: nowUtcStr);
      if (mounted) {
        setState(() {
          _checkedOut.add(slot.id);
          _checkedOutTimes[slot.id] = nowHHMM;
        });
        _showSuccessSnackbar('👋 Ausgecheckt um $nowHHMM Uhr');
      }
    } catch (e) {
      debugPrint('SelfCheckin: Netzwerkfehler bei checkOutSlot, reihe in SyncQueue ein: $e');
      final offlinePayload = {
        'checkout': nowUtcStr,
        'status': 'Durchgeführt',
      };
      await _syncQueue.enqueue(
        slotId: slot.id,
        data: offlinePayload,
        description: 'Check-Out ${slot.name} ($nowHHMM)',
      );

      if (mounted) {
        setState(() {
          _checkedOut.add(slot.id);
          _checkedOutTimes[slot.id] = nowHHMM;
        });
        _showSuccessSnackbar('👋 Ausgecheckt! (Offline gespeichert – wird bei Netz automatisch synchronisiert)');
      }
    }

    await _saveLocalState();
    if (mounted) setState(() => _isProcessing = false);
  }

  void _showGpsErrorDialog(GpsCheckResult result, Slot slot) {
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
          ],
        ),
        actions: [
          if (result.address != null || result.targetLat != null)
            TextButton.icon(
              icon: const Icon(Icons.directions),
              label: const Text('Route anzeigen'),
              onPressed: () {
                Navigator.pop(ctx);
                _location.openNavigation(
                  lat: result.targetLat,
                  lon: result.targetLon,
                  address: result.address,
                );
              },
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

  void _showSuccessSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstempeln / Check-In'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Schichten aktualisieren',
            onPressed: _loadTodaysSlots,
          ),
        ],
      ),
      body: Column(
        children: [
          // Datums-Header
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

          if (_isProcessing)
            const LinearProgressIndicator(),

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
                    : _slots.isEmpty
                        ? _buildNoShifts()
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _slots.length,
                            itemBuilder: (ctx, i) => _buildSlotCard(_slots[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoShifts() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_available, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('Keine Schichten für heute', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Du hast für den heutigen Tag keine geplanten Einsätze.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildSlotCard(Slot slot) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isIn = _checkedIn.contains(slot.id) || (slot.checkin != null && slot.checkin!.isNotEmpty);
    final isOut = _checkedOut.contains(slot.id) || (slot.checkout != null && slot.checkout!.isNotEmpty);

    final inTime = _checkedTimes[slot.id] ??
        (slot.checkin != null ? (slot.checkin!.contains(' ') ? slot.checkin!.split(' ')[1].substring(0, 5) : slot.checkin!.substring(0, 5)) : '');
    final outTime = _checkedOutTimes[slot.id] ??
        (slot.checkout != null ? (slot.checkout!.contains(' ') ? slot.checkout!.split(' ')[1].substring(0, 5) : slot.checkout!.substring(0, 5)) : '');

    final ampel = _slotAmpeln[slot.id] ?? '🟢';

    Color statusColor = isOut ? Colors.blueGrey : (isIn ? Colors.green : Colors.orange);
    String statusText = isOut ? '🏁 Abgeschlossen' : (isIn ? '🟢 Eingecheckt' : '⚪ Geplant / Wartend');

    final fmt = DateFormat('HH:mm');
    String? startStr, endStr;
    try {
      if (slot.dateStart != null) startStr = fmt.format(DateFormat('yyyy-MM-dd HH:mm:ss').parseUtc(slot.dateStart!).toLocal());
      if (slot.dateEnd != null) endStr = fmt.format(DateFormat('yyyy-MM-dd HH:mm:ss').parseUtc(slot.dateEnd!).toLocal());
    } catch (_) {}

    return Card(
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
            // Status-Badge & Zeit
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

            // 1-Tap Aktions-Buttons (Terminal-Vorbild)
            Row(
              children: [
                if (!isIn && !isOut)
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.login, size: 20),
                        label: const Text('Vor Ort Einchecken', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Auschecken', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
