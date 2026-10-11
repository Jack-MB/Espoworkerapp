import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/slot.dart';
import 'api_service.dart';
import '../utils/espo_date.dart';

/// Zentraler State-Service für Check-In, Check-Out und Ordnernummern.
/// Garantiert absolute Interaktivität und Synchronität zwischen allen Bildschirmen:
/// - Dashboard-Kalender
/// - Schichtenliste & Schichtdetail
/// - Dedizierter Einstempeln-Screen
class CheckinStateService extends ChangeNotifier {
  static final CheckinStateService _instance = CheckinStateService._internal();
  factory CheckinStateService() => _instance;
  CheckinStateService._internal();

  final ApiService _api = ApiService();

  bool _isGloballyEnabled = true;
  bool get isGloballyEnabled => _isGloballyEnabled;

  Set<String> _checkedInSlotIds = {};
  Set<String> get checkedInSlotIds => Set.unmodifiable(_checkedInSlotIds);

  Set<String> _checkedOutSlotIds = {};
  Set<String> get checkedOutSlotIds => Set.unmodifiable(_checkedOutSlotIds);

  Map<String, String> _checkedInTimes = {};
  Map<String, String> get checkedInTimes => Map.unmodifiable(_checkedInTimes);

  Map<String, String> _checkedOutTimes = {};
  Map<String, String> get checkedOutTimes => Map.unmodifiable(_checkedOutTimes);

  final Map<String, String> _slotAmpeln = {};
  Map<String, String> get slotAmpeln => Map.unmodifiable(_slotAmpeln);

  final Map<String, String> _slotOrdnerNummern = {};
  Map<String, String> get slotOrdnerNummern => Map.unmodifiable(_slotOrdnerNummern);

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    await _loadFromLocal();
    await refreshGlobalConfig();
    _initialized = true;
    notifyListeners();
  }

  Future<void> _loadFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _checkedInSlotIds = (prefs.getStringList('admin_checked_slots') ?? []).toSet();
      _checkedOutSlotIds = (prefs.getStringList('admin_checked_out_slots') ?? []).toSet();
      final inJson = prefs.getString('admin_checked_times');
      final outJson = prefs.getString('admin_checked_out_times');
      if (inJson != null && inJson.trim().isNotEmpty) {
        try {
          _checkedInTimes = Map<String, String>.from(json.decode(inJson));
        } catch (_) {}
      }
      if (outJson != null && outJson.trim().isNotEmpty) {
        try {
          _checkedOutTimes = Map<String, String>.from(json.decode(outJson));
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('CheckinStateService._loadFromLocal error: $e');
    }
  }

  Future<void> _saveToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('admin_checked_slots', _checkedInSlotIds.toList());
      await prefs.setStringList('admin_checked_out_slots', _checkedOutSlotIds.toList());
      await prefs.setString('admin_checked_times', json.encode(_checkedInTimes));
      await prefs.setString('admin_checked_out_times', json.encode(_checkedOutTimes));
    } catch (e) {
      debugPrint('CheckinStateService._saveToLocal error: $e');
    }
  }

  /// Prüft die globale Einstellung (Aktiv/Inaktiv) vom EspoCRM Backend
  Future<bool> refreshGlobalConfig() async {
    try {
      final enabled = await _api.getCheckinConfig();
      if (_isGloballyEnabled != enabled) {
        _isGloballyEnabled = enabled;
        notifyListeners();
      }
      return enabled;
    } catch (_) {
      return _isGloballyEnabled;
    }
  }

  /// Schaltet den globalen Check-in systemweit um (nur für Admins)
  Future<bool> setGlobalCheckinEnabled(bool enabled) async {
    final ok = await _api.setCheckinConfig(enabled);
    if (ok) {
      _isGloballyEnabled = enabled;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Registriert Slot-Daten vom Server und synchronisiert sofort den App-State
  void syncSlotFromServer(Slot slot) {
    bool changed = false;
    if (slot.cI != null && slot.cI!.isNotEmpty) {
      if (_slotAmpeln[slot.id] != slot.cI) {
        _slotAmpeln[slot.id] = slot.cI!;
        changed = true;
      }
    }
    if (slot.oNr != null && slot.oNr!.isNotEmpty) {
      if (_slotOrdnerNummern[slot.id] != slot.oNr) {
        _slotOrdnerNummern[slot.id] = slot.oNr!;
        changed = true;
      }
    }
    if (slot.checkin != null && slot.checkin!.isNotEmpty) {
      if (!_checkedInSlotIds.contains(slot.id)) {
        _checkedInSlotIds.add(slot.id);
        changed = true;
      }
      final localIn = formatUtcToLocalTime(slot.checkin);
      if (localIn != null && _checkedInTimes[slot.id] != localIn) {
        _checkedInTimes[slot.id] = localIn;
        changed = true;
      }
    }
    if (slot.checkout != null && slot.checkout!.isNotEmpty) {
      if (!_checkedOutSlotIds.contains(slot.id)) {
        _checkedOutSlotIds.add(slot.id);
        changed = true;
      }
      final localOut = formatUtcToLocalTime(slot.checkout);
      if (localOut != null && _checkedOutTimes[slot.id] != localOut) {
        _checkedOutTimes[slot.id] = localOut;
        changed = true;
      }
    }
    if (changed) {
      _saveToLocal();
      notifyListeners();
    }
  }

  /// Batch-Synchronisation für eine Liste von Slots (z.B. nach Server-Abruf)
  void syncSlotsFromServer(List<Slot> slots) {
    bool anyChanged = false;
    for (final slot in slots) {
      if (slot.cI != null && slot.cI!.isNotEmpty) {
        if (_slotAmpeln[slot.id] != slot.cI) {
          _slotAmpeln[slot.id] = slot.cI!;
          anyChanged = true;
        }
      }
      if (slot.oNr != null && slot.oNr!.isNotEmpty) {
        if (_slotOrdnerNummern[slot.id] != slot.oNr) {
          _slotOrdnerNummern[slot.id] = slot.oNr!;
          anyChanged = true;
        }
      }
      if (slot.checkin != null && slot.checkin!.isNotEmpty) {
        if (!_checkedInSlotIds.contains(slot.id)) {
          _checkedInSlotIds.add(slot.id);
          anyChanged = true;
        }
        final localIn = formatUtcToLocalTime(slot.checkin);
        if (localIn != null && _checkedInTimes[slot.id] != localIn) {
          _checkedInTimes[slot.id] = localIn;
          anyChanged = true;
        }
      }
      if (slot.checkout != null && slot.checkout!.isNotEmpty) {
        if (!_checkedOutSlotIds.contains(slot.id)) {
          _checkedOutSlotIds.add(slot.id);
          anyChanged = true;
        }
        final localOut = formatUtcToLocalTime(slot.checkout);
        if (localOut != null && _checkedOutTimes[slot.id] != localOut) {
          _checkedOutTimes[slot.id] = localOut;
          anyChanged = true;
        }
      }
    }
    if (anyChanged) {
      _saveToLocal();
      notifyListeners();
    }
  }

  /// Führt den Check-In für eine Schicht aus und benachrichtigt alle Screens sofort
  Future<Map<String, dynamic>> performCheckIn(Slot slot, {String? oNr, String? customTimeUtc}) async {
    final now = DateTime.now();
    final localTimeStr = DateFormat('HH:mm').format(now);
    final utcTimeStr = customTimeUtc ?? now.toUtc().toIso8601String();

    _checkedInSlotIds.add(slot.id);
    _checkedInTimes[slot.id] = localTimeStr;
    if (oNr != null && oNr.isNotEmpty) {
      _slotOrdnerNummern[slot.id] = oNr;
    }
    await _saveToLocal();
    notifyListeners();

    try {
      final success = await _api.checkInSlot(slot.id, checkInTime: utcTimeStr, oNr: oNr);
      return {
        'success': success,
        'offline': false,
        'time': localTimeStr,
        'ampel': _slotAmpeln[slot.id] ?? '🟢',
      };
    } catch (e) {
      return {
        'success': true,
        'offline': true,
        'time': localTimeStr,
        'ampel': _slotAmpeln[slot.id] ?? '🟢',
      };
    }
  }

  /// Führt den Check-Out für eine Schicht aus und benachrichtigt alle Screens sofort
  Future<Map<String, dynamic>> performCheckOut(Slot slot, {String? customTimeUtc}) async {
    final now = DateTime.now();
    final localTimeStr = DateFormat('HH:mm').format(now);
    final utcTimeStr = customTimeUtc ?? now.toUtc().toIso8601String();

    _checkedOutSlotIds.add(slot.id);
    _checkedOutTimes[slot.id] = localTimeStr;
    await _saveToLocal();
    notifyListeners();

    try {
      final success = await _api.checkOutSlot(slot.id, checkOutTime: utcTimeStr);
      return {
        'success': success,
        'offline': false,
        'time': localTimeStr,
      };
    } catch (e) {
      return {
        'success': true,
        'offline': true,
        'time': localTimeStr,
      };
    }
  }

  /// Setzt den Check-In-Status einer Schicht zurück (z.B. bei Admin-Abwahl)
  Future<void> revertCheckIn(Slot slot) async {
    _checkedInSlotIds.remove(slot.id);
    _checkedInTimes.remove(slot.id);
    _slotAmpeln.remove(slot.id);
    await _saveToLocal();
    notifyListeners();
  }

  /// Setzt den Check-Out-Status einer Schicht zurück
  Future<void> revertCheckOut(Slot slot) async {
    _checkedOutSlotIds.remove(slot.id);
    _checkedOutTimes.remove(slot.id);
    await _saveToLocal();
    notifyListeners();
  }

  /// Aktualisiert die Ordnernummer einer Schicht (Einsatzleiter / Admin)
  Future<bool> updateOrdnerNummer(String slotId, String? oNr) async {
    if (oNr != null && oNr.trim().isNotEmpty) {
      _slotOrdnerNummern[slotId] = oNr.trim();
    } else {
      _slotOrdnerNummern.remove(slotId);
    }
    notifyListeners();
    return await _api.updateOrdnerNummer(slotId, oNr);
  }

  // Hilfsmethoden für Widgets
  bool isCheckedIn(String slotId) => _checkedInSlotIds.contains(slotId);
  bool isCheckedOut(String slotId) => _checkedOutSlotIds.contains(slotId);
  String? getCheckInTime(String slotId) => _checkedInTimes[slotId];
  String? getCheckOutTime(String slotId) => _checkedOutTimes[slotId];
  String? getSlotAmpel(String slotId) => _slotAmpeln[slotId];
  String? getOrdnerNummer(String slotId) => _slotOrdnerNummern[slotId];
}
