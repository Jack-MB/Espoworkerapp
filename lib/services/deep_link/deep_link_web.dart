// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import "dart:html" as html;
import "deep_link_stub.dart";

class DeepLinkPlatformWeb implements DeepLinkPlatform {
  void Function(String slotId)? _callback;

  DeepLinkPlatformWeb() {
    html.window.onHashChange.listen((event) {
      final slotId = _extractSlotId(html.window.location.hash);
      if (slotId != null && _callback != null) {
        _callback!(slotId);
      }
    });

    html.window.addEventListener("mb_notification_click", (event) {
      if (event is html.CustomEvent && event.detail != null) {
        final slotId = _extractSlotId(event.detail.toString());
        if (slotId != null && _callback != null) {
          _callback!(slotId);
        }
      }
    });
  }

  @override
  String? getInitialSlotId() {
    final fragment = html.window.location.hash;
    return _extractSlotId(fragment);
  }

  @override
  void onSlotDeepLink(void Function(String slotId) callback) {
    _callback = callback;
  }

  @override
  void clearDeepLink() {
    try {
      if (html.window.location.hash.contains("Slots/view/")) {
        html.window.history.replaceState(null, "", html.window.location.pathname ?? "/");
      }
    } catch (_) {}
  }

  String? _extractSlotId(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final regExp = RegExp(r"Slots/view/([a-zA-Z0-9]{15,25})");
    final match = regExp.firstMatch(raw);
    return match?.group(1);
  }
}

DeepLinkPlatform getDeepLinkPlatform() => DeepLinkPlatformWeb();
