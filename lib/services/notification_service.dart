import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart';
import '../screens/slots_screen.dart';
import '../screens/wachbuch_list_screen.dart';
import '../screens/urlaub_screen.dart';
import '../screens/krankentage_screen.dart';
import '../screens/abwesenheit_screen.dart';
import '../screens/meeting_list_screen.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;

    _plugin = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Main initialization is required for the plugin to work
    await _plugin!.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        if (details.payload != null && details.payload!.isNotEmpty) {
           _handleNotificationPayload(details.payload!);
        }
      },
    );

    final androidPlugin = _plugin!.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'espo_crm_channel',
        'EspoCRM Benachrichtigungen',
        description: 'Benachrichtigungen von EspoCRM',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      await androidPlugin.createNotificationChannel(channel);
      
      // On Android 13+, we must request permission
      await androidPlugin.requestNotificationsPermission();
    }

    _initialized = true;
  }

  void _handleNotificationPayload(String payload) {
    if (EspoWorkerApp.navigatorKey.currentState == null) return;
    
    Widget? target;
    switch (payload) {
      case 'CWachbuch':
        target = const WachbuchListScreen();
        break;
      case 'Slot':
      case 'Slots':
        target = const SlotsScreen();
        break;
      case 'Urlaub':
        target = const UrlaubScreen();
        break;
      case 'Krankentage':
        target = const KrankentageScreen();
        break;
      case 'Abwesenheit':
        target = const AbwesenheitScreen();
        break;
      case 'Meeting':
        target = const MeetingListScreen();
        break;
    }

    if (target != null) {
      EspoWorkerApp.navigatorKey.currentState!.push(
        MaterialPageRoute(builder: (context) => target!),
      );
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized || _plugin == null) return;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'espo_crm_channel',
      'EspoCRM Benachrichtigungen',
      channelDescription: 'Benachrichtigungen von EspoCRM',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin!.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
