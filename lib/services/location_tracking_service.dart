import 'dart:async';
import 'dart:io' show Platform;
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'api_service.dart';
import 'notification_service.dart';

/**
 * Service für extrem stromsparenden Alleinarbeiterschutz (DGUV V23).
 * Weckt die Ortung nur punktuell alle X Minuten auf, holt einen Quick-Fix,
 * erfasst Akku- und Telemetriedaten und schaltet GPS sofort wieder schlafen.
 */
class LocationTrackingService {
  static final LocationTrackingService _instance = LocationTrackingService._internal();
  factory LocationTrackingService() => _instance;
  LocationTrackingService._internal();

  static const int trackingNotificationId = 9923;

  Timer? _timer;
  String? _activeSlotId;
  int _intervalMinutes = 10;
  bool _isTracking = false;
  DateTime? _lastPingTime;
  int? _lastBatteryLevel;

  bool get isTracking => _isTracking;
  String? get activeSlotId => _activeSlotId;
  int get intervalMinutes => _intervalMinutes;
  DateTime? get lastPingTime => _lastPingTime;
  int? get lastBatteryLevel => _lastBatteryLevel;

  final ApiService _apiService = ApiService();
  final Battery _battery = Battery();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Startet das periodische Tracking für eine Alleinarbeitsschicht
  Future<void> startTracking({
    required String slotId,
    int intervalMinutes = 10,
    String? objectName,
  }) async {
    if (_isTracking && _activeSlotId == slotId) {
      debugPrint('[Tracking] Tracking läuft bereits für Schicht $slotId');
      return;
    }

    _activeSlotId = slotId;
    _intervalMinutes = intervalMinutes > 0 ? intervalMinutes : 10;
    _isTracking = true;

    debugPrint('[Tracking] Starte Alleinarbeiterschutz für Schicht $slotId (Intervall: $_intervalMinutes Min.)');

    // Initialen Ping sofort ausführen
    await executePing();

    // Timer für periodische Pings starten
    _timer?.cancel();
    _timer = Timer.periodic(Duration(minutes: _intervalMinutes), (timer) {
      if (!_isTracking || _activeSlotId == null) {
        timer.cancel();
        return;
      }
      executePing();
    });
  }

  /// Beendet das Tracking (z. B. bei Schichtende / Check-Out)
  Future<void> stopTracking() async {
    debugPrint('[Tracking] Beende Alleinarbeiterschutz für Schicht $_activeSlotId');
    _isTracking = false;
    _activeSlotId = null;
    _timer?.cancel();
    _timer = null;

    try {
      await NotificationService().cancelNotification(trackingNotificationId);
    } catch (e) {
      debugPrint('[Tracking] Fehler beim Entfernen der Benachrichtigung: $e');
    }
  }

  /// Führt einen einzelnen, extrem stromsparenden GPS-Fix durch
  Future<bool> executePing() async {
    if (_activeSlotId == null) return false;

    try {
      // 1. Berechtigungen prüfen
      final permission = await _checkAndRequestPermission();
      if (!permission) {
        debugPrint('[Tracking] Standort-Berechtigung nicht erteilt.');
        return false;
      }

      // 2. Stromsparenden GPS-Fix ermitteln (Medium-Genauigkeit, max 10 Sekunden)
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        debugPrint('[Tracking] getCurrentPosition Timeout/Fehler, nutze getLastKnownPosition: $e');
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        debugPrint('[Tracking] Kein Standort-Fix ermittelbar.');
        return false;
      }

      // 3. Akkustand ermitteln
      int? batteryLevel;
      try {
        batteryLevel = await _battery.batteryLevel;
        _lastBatteryLevel = batteryLevel;
      } catch (_) {}

      // 4. Gerätebezeichnung ermitteln
      final deviceStr = await _getDeviceString();

      // 5. Ping an den EspoCRM Server senden
      final success = await _apiService.sendLiveTrackingPing(
        slotId: _activeSlotId!,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        batteryLevel: batteryLevel,
        device: deviceStr,
        recordedAt: DateTime.now().toUtc(),
      );

      if (success) {
        _lastPingTime = DateTime.now();
        debugPrint('[Tracking] Live-Ping erfolgreich gesendet: ${position.latitude}, ${position.longitude} (Akku: $batteryLevel%)');
      }

      return success;
    } catch (e) {
      debugPrint('[Tracking] Fehler in executePing: $e');
      return false;
    }
  }

  Future<bool> _checkAndRequestPermission() async {
    if (kIsWeb) return true;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<String> _getDeviceString() async {
    if (kIsWeb) return 'Web / Browser';
    try {
      PackageInfo? pkg;
      try {
        pkg = await PackageInfo.fromPlatform();
      } catch (_) {}
      final appVer = pkg != null ? 'v${pkg.version}+${pkg.buildNumber}' : 'Worker App';

      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return '$appVer (${info.manufacturer} ${info.model}, Android ${info.version.release})';
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return '$appVer (${info.name}, iOS ${info.systemVersion})';
      }
      return '$appVer (${Platform.operatingSystem})';
    } catch (_) {
      return 'MB-Worker App';
    }
  }
}
