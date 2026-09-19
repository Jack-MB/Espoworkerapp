abstract class DeepLinkPlatform {
  String? getInitialSlotId();
  void onSlotDeepLink(void Function(String slotId) callback);
  void clearDeepLink();
}

class DeepLinkPlatformStub implements DeepLinkPlatform {
  @override
  String? getInitialSlotId() => null;

  @override
  void onSlotDeepLink(void Function(String slotId) callback) {}

  @override
  void clearDeepLink() {}
}

DeepLinkPlatform getDeepLinkPlatform() => DeepLinkPlatformStub();
