import "deep_link/deep_link_stub.dart"
    if (dart.library.html) "deep_link/deep_link_web.dart";

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final _platform = getDeepLinkPlatform();

  String? getInitialSlotId() => _platform.getInitialSlotId();
  void onSlotDeepLink(void Function(String slotId) callback) =>
      _platform.onSlotDeepLink(callback);
  void clearDeepLink() => _platform.clearDeepLink();
}
