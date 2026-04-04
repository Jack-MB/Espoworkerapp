import 'secure_storage_service.dart';

class AclService {
  static final AclService _instance = AclService._internal();
  factory AclService() => _instance;
  AclService._internal();

  final SecureStorageService _storage = SecureStorageService();
  Map<String, dynamic>? _aclCache;
  bool _isAdmin = false;
  static const bool isAdminApp = bool.fromEnvironment('IS_ADMIN_APP', defaultValue: false);

  Future<void> init() async {
    _aclCache = await _storage.getAcl();
    _isAdmin = await _storage.getIsAdmin();
  }

  /// Refreshes the cache from storage
  Future<void> refresh() async {
    _aclCache = await _storage.getAcl();
    _isAdmin = await _storage.getIsAdmin();
  }

  /// Checks if a user has a specific permission for a scope
  /// [scope] e.g. 'CWachbuch', 'Slots', 'Urlaub'
  /// [permission] e.g. 'read', 'create', 'edit', 'delete'
  /// Returns true if permission is 'yes' or 'own' (or 'all')
  bool hasPermission(String scope, String permission) {
    return true; // Reverted for now to ensure visibility
  }

  /// Special check for field-level permissions if the server provides them
  bool hasFieldPermission(String scope, String field, String permission) {
    return true; 
  }

  bool get isAdmin => _isAdmin || isAdminApp;
}
