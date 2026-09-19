/// Web-Implementierung der biometrischen Authentifizierung via WebAuthn.
/// Wird nur für Web-Builds kompiliert (dart.library.html konditionaler Import).
library web_biometric_impl;

import 'dart:js_interop';

// ── Direkte JavaScript-Bindings über dart:js_interop ──────────────────────

@JS('mbWebAuthn.isPlatformAvailable')
external JSPromise<JSBoolean> _jsIsPlatformAvailable();

@JS('mbWebAuthn.isBiometricEnabled')
external bool _jsIsBiometricEnabled();

@JS('mbWebAuthn.register')
external JSPromise<JSAny?> _jsRegister(JSString userId, JSString username);

@JS('mbWebAuthn.authenticate')
external JSPromise<JSBoolean> _jsAuthenticate();

@JS('mbWebAuthn.clear')
external void _jsClear();

@JS('window.location.reload')
external void _jsReload(bool forceGet);

// ── Dart-Funktionen, die vom WebBiometricService genutzt werden ────────────

/// Prüft ob der Browser einen Plattform-Authenticator (Biometrie) unterstützt.
Future<bool> webAuthnIsPlatformAvailable() async {
  try {
    final result = await _jsIsPlatformAvailable().toDart;
    return result.toDart;
  } catch (_) {
    return false;
  }
}

/// Prüft ob Biometrie bereits registriert ist (Credential in localStorage).
bool webAuthnIsBiometricEnabled() {
  try {
    return _jsIsBiometricEnabled();
  } catch (_) {
    return false;
  }
}

/// Registriert einen neuen WebAuthn-Credential für den Nutzer.
/// Gibt die Credential-ID (base64) zurück oder null bei Fehler/Abbruch.
Future<String?> webAuthnRegister(String userId, String username) async {
  try {
    final result = await _jsRegister(userId.toJS, username.toJS).toDart;
    if (result == null) return null;
    return (result as JSString).toDart;
  } catch (_) {
    return null;
  }
}

/// Löst den biometrischen Authentifizierungs-Dialog aus.
/// Gibt true zurück bei Erfolg, false bei Fehler oder Abbruch.
Future<bool> webAuthnAuthenticate() async {
  try {
    final result = await _jsAuthenticate().toDart;
    return result.toDart;
  } catch (_) {
    return false;
  }
}

/// Löscht gespeicherte WebAuthn-Daten (Credential-ID aus localStorage).
void webAuthnClear() {
  try {
    _jsClear();
  } catch (_) {}
}

void webAuthnReloadWeb() {
  _jsReload(true);
}
