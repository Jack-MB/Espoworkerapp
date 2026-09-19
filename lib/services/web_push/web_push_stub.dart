class WebPushPlatform {
  Future<bool> initWebPush() async => false;
  bool get shouldShowIosTutorial => false;
  String getNotificationPermission() => 'granted';
  bool isIosDevice() => false;
}

WebPushPlatform getWebPushPlatform() => WebPushPlatform();
