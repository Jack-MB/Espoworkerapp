/// Stub-Implementierung für native Plattformen (Android/iOS).
/// WebAuthn ist nur im Browser verfügbar — auf nativen Plattformen wird local_auth verwendet.

Future<bool> webAuthnIsPlatformAvailable() async => false;
bool webAuthnIsBiometricEnabled() => false;
void checkWebBiometricAvailability() {}
void webAuthnReloadWeb() {}
Future<String?> webAuthnRegister(String userId, String username) async => null;
Future<bool> webAuthnAuthenticate() async => false;
void webAuthnClear() {}
