import 'web_push/web_push_stub.dart'
    if (dart.library.js_interop) 'web_push/web_push_web.dart';

class WebPushService {
  static final WebPushService _instance = WebPushService._internal();
  factory WebPushService() => _instance;
  WebPushService._internal();

  final _platform = getWebPushPlatform();

  Future<bool> initWebPush() => _platform.initWebPush();
  bool get shouldShowIosTutorial => _platform.shouldShowIosTutorial;
  String getNotificationPermission() => _platform.getNotificationPermission();
  bool isIosDevice() => _platform.isIosDevice();
}
