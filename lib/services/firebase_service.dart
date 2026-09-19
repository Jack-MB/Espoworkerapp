import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../firebase_options.dart';
import 'secure_storage_service.dart';
import 'api_service.dart';
import 'notification_service.dart';

// Globale Handler-Funktion für Push-Nachrichten, wenn die App im Hintergrund / geschlossen ist
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    debugPrint("Handling a background message: ${message.messageId}");
  } catch (e) {
    debugPrint("Background message handler error: $e");
  }
}

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  FirebaseMessaging? _messagingInstance;
  FirebaseMessaging get _messaging => _messagingInstance ??= FirebaseMessaging.instance;

  bool _isInitialized = false;

  Future<void> init() async {
    if (kIsWeb) return;
    if (_isInitialized) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      
      // Im Hintergrund behandeln
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Token-Aktualisierungen beobachten
      _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('FCM Token refreshed: $newToken');
        await SecureStorageService().write('fcm_token', newToken);
        final result = await ApiService().syncFcmToken(newToken);
        debugPrint('FCM Refresh Sync: $result');
      });

      // Nachrichten im Vordergrund behandeln
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message data: ${message.data}');

        if (message.notification != null) {
          debugPrint('Message notification: ${message.notification?.title} - ${message.notification?.body}');
          NotificationService().showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: message.notification?.title ?? 'EspoCRM Benachrichtigung',
            body: message.notification?.body ?? '',
            payload: message.data['entityType']?.toString(),
          );
        }
      });

      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing Firebase: $e');
      rethrow;
    }
  }

  /// Gibt den aktuell gespeicherten oder direkt von Firebase abgerufenen Token zurück
  Future<String?> getStoredOrCurrentToken() async {
    final stored = await SecureStorageService().read('fcm_token');
    if (stored != null && stored.isNotEmpty) return stored;
    try {
      if (!kIsWeb) {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        final token = await _messaging.getToken();
        if (token != null && token.isNotEmpty) {
          await SecureStorageService().write('fcm_token', token);
          return token;
        }
      }
    } catch (e) {
      debugPrint('getStoredOrCurrentToken error: $e');
    }
    return null;
  }

  /// Fragt die Systemberechtigungen an (Android 13+ & iOS) und synchronisiert den FCM-Token sofort mit EspoCRM
  /// Wirft eine Exception bei Fehlern, damit die UI die genaue Ursache anzeigen kann.
  Future<String> requestPermissionAndSyncToken() async {
    if (kIsWeb) {
      throw UnsupportedError('Verwende WebPushService für Web-Push');
    }

    // 1. Firebase initialisieren falls noch nicht geschehen
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // 2. Android Benachrichtigungs-Berechtigung (Android 13+) anfragen
    if (Platform.isAndroid) {
      try {
        await NotificationService().requestPermission();
      } catch (e) {
        debugPrint('NotificationService permission error: $e');
      }
    } else if (Platform.isIOS) {
      try {
        await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (e) {
        debugPrint('iOS permission error: $e');
      }
    }

    // 3. Token von Firebase abrufen
    String? token;
    try {
      token = await _messaging.getToken();
    } catch (e) {
      debugPrint('Firebase getToken error: $e');
      throw Exception('Firebase-Fehler: $e');
    }

    if (token == null || token.isEmpty) {
      throw Exception('FCM hat keinen Token geliefert (null). Google Play Dienste prüfen.');
    }

    // 4. Token lokal speichern
    await SecureStorageService().write('fcm_token', token);

    // 5. Token mit EspoCRM synchronisieren
    final syncResult = await ApiService().syncFcmToken(token);
    debugPrint('Firebase Token synced to EspoCRM: $syncResult');

    if (syncResult.contains('Fehler: Kein Token')) {
      throw Exception('Token konnte nicht gespeichert werden: $syncResult');
    }

    return token;
  }
}
