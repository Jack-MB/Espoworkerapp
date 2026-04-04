import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    
    print("Background polling executed: $task");
    try {
      final apiService = ApiService();
      
      final notifs = await apiService.getNotifications();
      final unreadNotifs = notifs.where((n) => !n.read).toList();
      
      if (unreadNotifs.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final lastNotifId = prefs.getString('last_notif_id');
        final currentLatestId = unreadNotifs.first.id;
        
        if (lastNotifId != currentLatestId) {
          await prefs.setString('last_notif_id', currentLatestId);
          
          // Show native push notification
          final notifService = NotificationService();
          await notifService.initialize();
          
          if (unreadNotifs.length == 1) {
            final notif = unreadNotifs.first;
            String? type = notif.relatedType;
            if (type == null && notif.noteData != null) {
              type = notif.noteData!['parentType'];
            }

            await notifService.showNotification(
              id: currentLatestId.hashCode,
              title: notif.title,
              body: notif.body,
              payload: type,
            );
          } else {
            await notifService.showNotification(
              id: currentLatestId.hashCode,
              title: '${unreadNotifs.length} neue Benachrichtigungen',
              body: 'Sie haben ungelesene Nachrichten in EspoCRM.',
              payload: null,
            );
          }
        }
      }
    } catch (err) {
      print("Polling Error: $err");
    }
    return Future.value(true);
  });
}

class PollingService {
  static const String _taskName = "com.espocrm.worker.backgroundSync";

  Future<void> initialize() async {
    if (kIsWeb) return;

    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  Future<void> schedulePolling(Duration interval) async {
    if (kIsWeb) return;
    
    await Workmanager().cancelAll();
    
    await Workmanager().registerPeriodicTask(
      "1",
      _taskName,
      frequency: interval,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  Future<void> stopPolling() async {
    if (kIsWeb) return;
    await Workmanager().cancelAll();
  }
}
