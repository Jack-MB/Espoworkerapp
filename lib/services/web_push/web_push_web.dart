import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/server_config.dart';
import '../secure_storage_service.dart';
import 'web_push_stub.dart';

@JS('subscribeToWebPush')
external JSPromise<JSString?> _subscribeToWebPush(JSString vapidPublicKey);

@JS('isIosStandalone')
external JSBoolean _isIosStandalone();

@JS('isIos')
external JSBoolean _isIos();

@JS('getNotificationPermission')
external JSString _getNotificationPermission();

class WebPushPlatformWeb implements WebPushPlatform {
  final SecureStorageService _storage = SecureStorageService();

  @override
  String getNotificationPermission() {
    if (!kIsWeb) return 'granted';
    try {
      return _getNotificationPermission().toDart;
    } catch (_) {
      return 'unsupported';
    }
  }

  @override
  bool isIosDevice() {
    if (!kIsWeb) return false;
    try {
      return _isIos().toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> initWebPush() async {
    if (!kIsWeb) return false;
    
    if (_isIos().toDart && !_isIosStandalone().toDart) {
      debugPrint("WebPush: User is on iOS Safari (not standalone). WebPush won't work without 'Add to Home Screen'.");
      throw Exception("Auf iOS muss die App zum Home-Bildschirm hinzugefügt werden ('Teilen' -> 'Zum Home-Bildschirm').");
    }

    final vapidKey = await _fetchVapidKey();
    if (vapidKey == null || vapidKey.isEmpty) {
      throw Exception('Konnte VAPID-Public-Key nicht vom Server abrufen.');
    }

    final subscriptionJson = await _subscribeToWebPush(vapidKey.toJS).toDart;
    if (subscriptionJson == null || subscriptionJson.toDart.isEmpty) {
      throw Exception('Browser hat keine Push-Subscription zurückgegeben.');
    }

    final dynamic subData = json.decode(subscriptionJson.toDart);
    if (subData is Map && subData.containsKey('error')) {
      throw Exception(subData['error'].toString());
    }

    if (subData is! Map<String, dynamic>) {
      throw Exception('Ungültige Antwort von Push-Manager erhalten.');
    }

    final syncSuccess = await _sendSubscriptionToServer(subData);
    if (!syncSuccess) {
      throw Exception('Abonnement konnte nicht mit EspoCRM synchronisiert werden.');
    }

    // Endpunkt / Token lokal speichern, damit Push-Status in der UI sichtbar ist
    final endpoint = subData['endpoint'] as String? ?? 'web-push-registered';
    await _storage.write('fcm_token', endpoint);
    return true;
  }

  Future<String?> _fetchVapidKey() async {
    try {
      final token = await _storage.getToken();
      if (token == null) return null;
      
      final url = Uri.parse('${ServerConfig().apiUrl}/PushSubscription/action/getVapidKey');
      final response = await http.get(url, headers: {
        'Accept': 'application/json',
        'Authorization': token,
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['publicKey'] as String?;
      }
    } catch (e) {
      debugPrint('Error fetching VAPID key: $e');
    }
    return null;
  }

  Future<bool> _sendSubscriptionToServer(Map<String, dynamic> subscription) async {
    try {
      final token = await _storage.getToken();
      if (token == null) return false;
      
      final endpoint = subscription['endpoint'];
      final p256dh = subscription['keys']?['p256dh'];
      final auth = subscription['keys']?['auth'];
      
      if (endpoint == null || p256dh == null || auth == null) return false;

      final url = Uri.parse('${ServerConfig().apiUrl}/PushSubscription/action/subscribe');
      final resp = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': token,
        },
        body: json.encode({
          'endpoint': endpoint,
          'keys': {
            'p256dh': p256dh,
            'auth': auth,
          },
          'userAgent': 'MB-Worker PWA (Flutter Web)',
        }),
      );
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint("WebPush Sync Error: $e");
      return false;
    }
  }

  @override
  bool get shouldShowIosTutorial {
    if (!kIsWeb) return false;
    return _isIos().toDart && !_isIosStandalone().toDart;
  }
}

WebPushPlatform getWebPushPlatform() => WebPushPlatformWeb();
