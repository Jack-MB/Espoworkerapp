import 'dart:io' show Platform;
import 'dart:math' show max;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/slot.dart';
import 'api_service.dart';
import 'acl_service.dart';

enum GpsStatus {
  success,
  noCoordinatesRequired,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  mockDetected,
  outsideRadius,
  error,
}

class GpsCheckResult {
  final bool isSuccess;
  final GpsStatus status;
  final String message;
  final double? rawDistance;
  final double? effectiveDistance;
  final double? accuracy;
  final double? allowedRadius;
  final double? targetLat;
  final double? targetLon;
  final String? address;

  const GpsCheckResult({
    required this.isSuccess,
    required this.status,
    required this.message,
    this.rawDistance,
    this.effectiveDistance,
    this.accuracy,
    this.allowedRadius,
    this.targetLat,
    this.targetLon,
    this.address,
  });

  factory GpsCheckResult.success({
    double? rawDistance,
    double? effectiveDistance,
    double? accuracy,
    double? allowedRadius,
    double? targetLat,
    double? targetLon,
  }) {
    return GpsCheckResult(
      isSuccess: true,
      status: GpsStatus.success,
      message: 'Standort erfolgreich verifiziert.',
      rawDistance: rawDistance,
      effectiveDistance: effectiveDistance,
      accuracy: accuracy,
      allowedRadius: allowedRadius,
      targetLat: targetLat,
      targetLon: targetLon,
    );
  }

  factory GpsCheckResult.noCoordinatesRequired() {
    return const GpsCheckResult(
      isSuccess: true,
      status: GpsStatus.noCoordinatesRequired,
      message: 'Keine GPS-Verifikation für dieses Objekt erforderlich.',
    );
  }

  factory GpsCheckResult.failed({
    required GpsStatus status,
    required String message,
    double? rawDistance,
    double? effectiveDistance,
    double? accuracy,
    double? allowedRadius,
    double? targetLat,
    double? targetLon,
    String? address,
  }) {
    return GpsCheckResult(
      isSuccess: false,
      status: status,
      message: message,
      rawDistance: rawDistance,
      effectiveDistance: effectiveDistance,
      accuracy: accuracy,
      allowedRadius: allowedRadius,
      targetLat: targetLat,
      targetLon: targetLon,
      address: address,
    );
  }
}

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final ApiService _api = ApiService();
  final AclService _acl = AclService();

  /// Überprüft den Standort des Benutzers gegen die Geofence-Vorgaben der Schicht.
  /// Berücksichtigt plattformspezifische Eigenheiten (Android vs. iOS vs. Web)
  /// und gewährt eine faire GPS-Genauigkeitstoleranz.
  Future<GpsCheckResult> checkGeofence(Slot slot) async {
    try {
      // 1. Zielkoordinaten und Erlaubten Radius bestimmen
      double? targetLat;
      double? targetLon;
      int allowedRadius = 30;

      // Primäre Quelle: Objekt-Koordinaten
      if (slot.objekteId != null) {
        try {
          final coords = await _api.getObjektCoordinates(slot.objekteId!);
          if (coords != null) {
            targetLat = coords['latk'] as double?;
            targetLon = coords['lonK'] as double?;
            allowedRadius = coords['rad'] as int? ?? 30;
          }
        } catch (e) {
          debugPrint('LocationService: Fehler beim Laden der Objektkoordinaten: $e');
        }
      }

      // Fallback: Direkt an der Schicht hinterlegte Koordinaten
      targetLat ??= slot.latk;
      targetLon ??= slot.lonK;

      // Wenn keine Koordinaten hinterlegt sind, ist kein Geofence nötig (z. B. Bürodienst)
      if (targetLat == null || targetLon == null || (targetLat == 0 && targetLon == 0)) {
        return GpsCheckResult.noCoordinatesRequired();
      }

      // Adress-String für eventuelle Navigation im Fehlerfall zusammenbauen
      final address = _formatAddress(slot);

      // 2. Standortdienste-Status prüfen
      bool serviceEnabled = true;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
      } catch (e) {
        debugPrint('LocationService: isLocationServiceEnabled check error: $e');
      }

      if (!serviceEnabled && !kIsWeb) {
        return GpsCheckResult.failed(
          status: GpsStatus.serviceDisabled,
          message: 'Standortdienste (GPS) sind auf dem Gerät deaktiviert. Bitte in den Systemeinstellungen aktivieren.',
          targetLat: targetLat,
          targetLon: targetLon,
          address: address,
        );
      }

      // 3. Berechtigungsabfrage (Plattform-sicher)
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return GpsCheckResult.failed(
            status: GpsStatus.permissionDenied,
            message: 'Standort-Berechtigung verweigert. Einchecken nur mit Standortfreigabe möglich.',
            targetLat: targetLat,
            targetLon: targetLon,
            address: address,
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return GpsCheckResult.failed(
          status: GpsStatus.permissionDeniedForever,
          message: 'Standort-Berechtigung dauerhaft verweigert. Bitte in den App-Einstellungen freigeben.',
          targetLat: targetLat,
          targetLon: targetLon,
          address: address,
        );
      }

      // 4. Aktuelle Position ermitteln (mit Timeout & Fallback)
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 12),
        );
      } catch (_) {
        // Fallback mit mittlerer Genauigkeit, falls High-Accuracy in Gebäuden länger braucht
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 8),
          );
        } catch (e) {
          // Fallback: Letzte bekannte Position prüfen (z. B. beim Betreten des Gebäudes)
          try {
            final lastKnown = await Geolocator.getLastKnownPosition();
            if (lastKnown != null &&
                DateTime.now().difference(lastKnown.timestamp).inMinutes <= 45) {
              position = lastKnown;
            }
          } catch (_) {}

          if (position == null) {
            return GpsCheckResult.failed(
              status: GpsStatus.error,
              message: 'Standort konnte im Gebäude nicht ermittelt werden (GPS-Timeout). Bitte prüfe deinen Empfang oder wende dich an die Einsatzleitung.',
              targetLat: targetLat,
              targetLon: targetLon,
              address: address,
            );
          }
        }
      }

      // 5. Anti-Spoofing / Mock-Location Prüfung (NUR auf Android Nativ verfügbar)
      if (!kIsWeb && Platform.isAndroid && position.isMocked) {
        if (!_acl.isAdmin) {
          // Betrugsversuch im Backend protokollieren
          try {
            await _api.patchSlot(slot.id, {'mockStandort': true});
          } catch (_) {}

          return GpsCheckResult.failed(
            status: GpsStatus.mockDetected,
            message: 'Sicherheitsfehler: Vorgetäuschter Standort (Fake GPS) erkannt. Check-In blockiert.',
            targetLat: targetLat,
            targetLon: targetLon,
            address: address,
          );
        }
      }

      // 6. Geofencing-Berechnung mit fairer Genauigkeitstoleranz
      final double rawDistance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        targetLat,
        targetLon,
      );

      // Fair Geofencing:
      // Auf Smartphones hat das GPS-Signal eine Ungenauigkeit (position.accuracy, z. B. ±10-25m).
      // Ein Mitarbeiter direkt am Objekt darf nicht abgewiesen werden, nur weil die Satelliten schwanken.
      final double accuracy = position.accuracy;
      final double effectiveDistance = max(0.0, rawDistance - accuracy);
      final double maxAllowed = allowedRadius.toDouble();

      if (effectiveDistance > maxAllowed) {
        return GpsCheckResult.failed(
          status: GpsStatus.outsideRadius,
          message: 'Du befindest dich ca. ${rawDistance.toStringAsFixed(0)} m vom Einsatzort entfernt '
              '(Erlaubter Radius: $allowedRadius m).\nCheck-In ist nur direkt vor Ort möglich.',
          rawDistance: rawDistance,
          effectiveDistance: effectiveDistance,
          accuracy: accuracy,
          allowedRadius: maxAllowed,
          targetLat: targetLat,
          targetLon: targetLon,
          address: address,
        );
      }

      return GpsCheckResult.success(
        rawDistance: rawDistance,
        effectiveDistance: effectiveDistance,
        accuracy: accuracy,
        allowedRadius: maxAllowed,
        targetLat: targetLat,
        targetLon: targetLon,
      );
    } catch (e) {
      debugPrint('LocationService checkGeofence unexpected error: $e');
      return GpsCheckResult.failed(
        status: GpsStatus.error,
        message: 'Unerwarteter GPS-Fehler: $e',
      );
    }
  }

  /// Öffnet die native Navigations-App (Apple Maps auf iOS, Google Maps auf Android/Web)
  Future<void> openNavigation({double? lat, double? lon, String? address}) async {
    Uri? uri;
    if (lat != null && lon != null && lat != 0 && lon != 0) {
      if (!kIsWeb && Platform.isIOS) {
        uri = Uri.parse('maps://?q=$lat,$lon');
      } else {
        uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
      }
    } else if (address != null && address.trim().isNotEmpty) {
      final encoded = Uri.encodeComponent(address.trim());
      if (!kIsWeb && Platform.isIOS) {
        uri = Uri.parse('maps://?q=$encoded');
      } else {
        uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
      }
    }

    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Fehler beim Öffnen der Navigation: $e');
      }
    }
  }

  String _formatAddress(Slot slot) {
    if (slot.neueobjektstrasse != null && slot.neueobjektstrasse!.isNotEmpty) {
      return '${slot.neueobjektstrasse}, ${slot.neueobjektplz ?? ""} ${slot.neueobjektort ?? ""}'.trim();
    }
    if (slot.firmastrasse != null && slot.firmastrasse!.isNotEmpty) {
      return '${slot.firmastrasse}, ${slot.firmaplz ?? ""} ${slot.firmaort ?? ""}'.trim();
    }
    return slot.objekteName ?? '';
  }
}
