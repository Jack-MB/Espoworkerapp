import '../services/secure_storage_service.dart';

/// Singleton that holds the dynamically configured EspoCRM server URL.
/// Must be initialized via [init] before any API calls are made.
class ServerConfig {
  static final ServerConfig _instance = ServerConfig._internal();
  factory ServerConfig() => _instance;
  ServerConfig._internal();

  String? _baseUrl;

  /// The base URL of the EspoCRM instance (e.g. https://crm.example.com)
  String get baseUrl => _baseUrl ?? '';

  /// The API endpoint URL (e.g. https://crm.example.com/api/v1)
  String get apiUrl => '$baseUrl/api/v1';

  /// Whether a server URL has been configured yet
  bool get isConfigured => _baseUrl != null && _baseUrl!.isNotEmpty;

  /// Load the saved server URL from secure storage.
  /// Call this once at app startup.
  Future<void> init() async {
    final storage = SecureStorageService();
    _baseUrl = await storage.getServerUrl();
  }

  /// Set the base URL in memory (does not persist).
  void setBaseUrl(String url) {
    // Normalize: remove trailing slash
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Validate, persist, and activate a new server URL.
  Future<void> saveAndSetBaseUrl(String url) async {
    setBaseUrl(url);
    final storage = SecureStorageService();
    await storage.saveServerUrl(_baseUrl!);
  }
}
