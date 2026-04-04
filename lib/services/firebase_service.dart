import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'secure_storage_service.dart';
import 'api_service.dart';

// Globale Handler-Funktion für Push-Nachrichten, wenn die App im Hintergrund / geschlossen ist
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      
      // Im Hintergrund behandeln
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Berechtigungen anfragen (iOS spezifisch, Android ab 13)
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('User granted permission: ${settings.authorizationStatus}');

      // Token generieren
      try {
        String? token = await _messaging.getToken();
        debugPrint('FCM Token: $token');
        
        if (token != null) {
          await SecureStorageService().write('fcm_token', token);
          final result = await ApiService().syncFcmToken();
          debugPrint('FCM Startup Sync: $result');
        } else {
          await SecureStorageService().write('fcm_token', 'null_token');
        }
      } catch (e) {
        debugPrint('FCM Token Error: $e');
        await SecureStorageService().write('fcm_token', 'Error: $e');
      }

      // Token Aktualisierungen beobachten
      _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('FCM Token refreshed: $newToken');
        await SecureStorageService().write('fcm_token', newToken);
        final result = await ApiService().syncFcmToken();
        debugPrint('FCM Refresh Sync: $result');
      });

      // Nachrichten im Vordergrund behandeln
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message data: ${message.data}');

        if (message.notification != null) {
          debugPrint('Message also contained a notification: ${message.notification}');
          // Hier könnte eine In-App Notification (Snackbar / Banner) gezeigt werden
        }
      });
      
    } catch (e) {
      debugPrint('Error initializing Firebase: $e');
    }
  }
}
