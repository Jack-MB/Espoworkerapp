/// WebBiometricService – Biometrische Anmeldung für die PWA (Browser).
///
/// Verwendet die Web Authentication API (WebAuthn / FIDO2) für:
/// - Touch ID (iPhone/iPad/Mac)
/// - Face ID (iPhone/iPad)
/// - Windows Hello (Fingerprint/Gesicht/PIN)
/// - Android Fingerabdruck/Gesichtserkennung (Chrome)
///
/// Auf nativen Plattformen (Android/iOS App) wird local_auth verwendet —
/// dieser Service ist nur für den Web/PWA-Kontext gedacht.
library web_biometric_service;

import 'web_biometric_stub.dart'
    if (dart.library.html) 'web_biometric_impl.dart';

class WebBiometricService {
  static final WebBiometricService _instance = WebBiometricService._();
  factory WebBiometricService() => _instance;
  WebBiometricService._();

  /// Prüft ob der Browser biometrische Authentifizierung unterstützt.
  /// Gibt false zurück auf nativen Plattformen (dort local_auth verwenden).
  Future<bool> isPlatformAvailable() => webAuthnIsPlatformAvailable();

  /// Prüft ob der Benutzer bereits Biometrie für diese App aktiviert hat.
  bool isBiometricEnabled() => webAuthnIsBiometricEnabled();

  /// Registriert Biometrie für den Benutzer nach erfolgreichem Login.
  /// [userId] – eindeutige ID (EspoCRM user ID oder username)
  /// [username] – Anzeigename für den OS-Biometrie-Dialog
  Future<String?> register(String userId, String username) =>
      webAuthnRegister(userId, username);

  /// Löst den biometrischen Authentifizierungs-Dialog aus.
  /// Gibt true zurück wenn der Benutzer sich erfolgreich authentifiziert hat.
  Future<bool> authenticate() => webAuthnAuthenticate();

  /// Deaktiviert Biometrie und löscht gespeicherte Credential-Daten.
  void clear() => webAuthnClear();

  /// Lädt die PWA hart neu
  void reloadWeb() => webAuthnReloadWeb();
}
