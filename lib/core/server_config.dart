/// Singleton that holds the dynamically configured EspoCRM server URL.
/// Must be initialized via [init] before any API calls are made.
class ServerConfig {
  static final ServerConfig _instance = ServerConfig._internal();
  factory ServerConfig() => _instance;
  ServerConfig._internal();

  /// The base URL of the EspoCRM instance (e.g. https://crm.example.com)
  String get baseUrl => 'https://mb-scc.net';

  /// The API endpoint URL (e.g. https://crm.example.com/api/v1)
  String get apiUrl => '$baseUrl/api/v1';

  /// Whether a server URL has been configured yet
  bool get isConfigured => true;

  /// Load the saved server URL from secure storage.
  /// Call this once at app startup.
  Future<void> init() async {
    // Hardcoded for PWA, no need to load
  }

  /// Set the base URL in memory (does not persist).
  void setBaseUrl(String url) {
    // Ignore
  }

  /// Validate, persist, and activate a new server URL.
  Future<void> saveAndSetBaseUrl(String url) async {
    // Ignore
  }
}
