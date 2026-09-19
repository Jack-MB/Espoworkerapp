import 'secure_storage_service.dart';

class AclService {
  static final AclService _instance = AclService._internal();
  factory AclService() => _instance;
  AclService._internal();

  final SecureStorageService _storage = SecureStorageService();
  Map<String, dynamic>? _aclCache;
  bool _isAdmin = false;
  bool _isAppManager = false;

  Future<void> init() async {
    _aclCache = await _storage.getAcl();
    _isAdmin = await _storage.getIsAdmin();
    _isAppManager = await _storage.getIsAppManager();
  }

  Future<void> refresh() async {
    _aclCache = await _storage.getAcl();
    _isAdmin = await _storage.getIsAdmin();
    _isAppManager = await _storage.getIsAppManager();
  }

  /// Returns the value of a named permission level (e.g. 'schichtAnnahme').
  /// EspoCRM sends these as top-level keys like "schichtAnnahmePermission": "yes"|"no"|"not-set"
  /// Returns 'yes', 'no', 'not-set', or null if not found.
  String? getPermissionLevel(String permissionName) {
    if (_isAdmin) return 'yes'; // Admins always have all permissions

    if (_aclCache == null) return null;

    // 1. Direct match
    if (_aclCache!.containsKey(permissionName)) {
      return _aclCache![permissionName]?.toString();
    }

    // 2. With "Permission" suffix (e.g. schichtAnnahme -> schichtAnnahmePermission)
    final keyWithPerm = '${permissionName}Permission';
    if (_aclCache!.containsKey(keyWithPerm)) {
      return _aclCache![keyWithPerm]?.toString();
    }

    // 3. Without "Permission" suffix (e.g. schichtAnnahmePermission -> schichtAnnahme)
    if (permissionName.endsWith('Permission')) {
      final keyWithout = permissionName.substring(0, permissionName.length - 10);
      if (_aclCache!.containsKey(keyWithout)) {
        return _aclCache![keyWithout]?.toString();
      }
    }

    // 4. Case-insensitive fallback
    final lower = permissionName.toLowerCase();
    for (final entry in _aclCache!.entries) {
      final entryLower = entry.key.toLowerCase();
      if (entryLower == lower ||
          entryLower == '${lower}permission' ||
          (lower.endsWith('permission') && entryLower == lower.substring(0, lower.length - 10))) {
        return entry.value?.toString();
      }
    }

    return null;
  }

  /// Returns true if the user has the named value-permission set to 'yes'.
  bool hasValuePermission(String permissionName) {
    if (_isAdmin) return true;
    return getPermissionLevel(permissionName) == 'yes';
  }

  /// Schicht-Annahme: darf der Benutzer Schichten annehmen/ablehnen?
  bool get canAcceptShifts =>
      hasValuePermission('schichtAnnahmePermission') ||
      hasValuePermission('schichtAnnahme');

  /// Vorplanung: darf der Benutzer den Planungsvorschlag starten?
  bool get canStartPlanung => hasValuePermission('planungsvorschlag');

  /// EL-Bereinigung: darf der Benutzer EL-Zugriff bereinigen?
  bool get canCleanupEL => hasValuePermission('einsatzleiterBereinigen');

  /// Checks if a user has a specific permission for a scope
  /// [scope] e.g. 'CWachbuch', 'Slots', 'Urlaub'
  /// [permission] e.g. 'read', 'create', 'edit', 'delete'
  bool hasPermission(String scope, String permission) {
    if (_isAdmin) return true;
    if (_aclCache == null) return true; // Fail-open if not loaded yet

    final table = _aclCache!['table'] as Map<String, dynamic>?;
    if (table == null) return true;

    final scopeData = table[scope];
    if (scopeData == null) return false;

    final value = scopeData[permission];
    if (value == null) return false;
    // 'all', 'own', 'team', 'yes' → has access; 'no', 'false' → no access
    return value != 'no' && value != false && value != 'false';
  }

  /// Special check for field-level permissions if the server provides them
  bool hasFieldPermission(String scope, String field, String permission) {
    if (_isAdmin) return true;
    if (_aclCache == null) return true;

    final fieldTable = _aclCache!['fieldTable'] as Map<String, dynamic>?;
    if (fieldTable == null) return true;

    final scopeFields = fieldTable[scope] as Map<String, dynamic>?;
    if (scopeFields == null) return true;

    final fieldData = scopeFields[field] as Map<String, dynamic>?;
    if (fieldData == null) return true;

    final value = fieldData[permission];
    return value != 'no' && value != false && value != 'false';
  }

  /// Whether the current USER is marked as an admin on the EspoCRM server.
  bool get isAdmin => _isAdmin;

  /// Whether the user has App Manager privileges (either explicitly set or via Admin).
  bool get isAppManager => _isAdmin || _isAppManager;

  /// Whether the user is allowed to use THIS specific app build (Flavor).
  /// Everyone is authorized in the unified app.
  bool get isAuthorized => true;
}
