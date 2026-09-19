import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage service that uses [flutter_secure_storage] (Keystore/Keychain) on
/// native platforms, and [SharedPreferences] (localStorage) on the web.
///
/// On web, flutter_secure_storage uses IndexedDB + Web Crypto for encryption.
/// This combination is unreliable in browser incognito/private modes and on
/// some Windows browsers because the IndexedDB encryption key becomes
/// inaccessible after the encryption context is reset. SharedPreferences
/// (localStorage) works correctly in all browser contexts within a session.
class SecureStorageService {
  // Native secure storage (Android Keystore / iOS Keychain)
  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // Web key prefix to avoid collisions with other SharedPreferences keys
  static const _webPrefix = 'mbsec_store_';

  static const _keyToken = 'auth_token';
  static const _keyUsername = 'username';
  static const _keyPassword = 'password';
  static const _keyAngestellteId = 'angestellteId';
  static const _keyAssignedUserId = 'assignedUserId';
  static const _keyAngestellteName = 'angestellteName';
  static const _keyAclData = 'acl_data';
  static const _keyIsAdmin = 'is_admin';
  static const _keyIsAppManager = 'is_app_manager';
  static const _keyServerUrl = 'server_url';
  static const _keyIsSammelkonto = 'is_sammelkonto';

  // ─── Primitive helpers ────────────────────────────────────────────────────

  Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_webPrefix$key', value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  Future<String?> _read(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_webPrefix$key');
    } else {
      return await _secureStorage.read(key: key);
    }
  }

  Future<void> delete(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_webPrefix$key');
    } else {
      await _secureStorage.delete(key: key);
    }
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  Future<void> saveToken(String token) async => _write(_keyToken, token);
  Future<String?> getToken() async => _read(_keyToken);

  Future<void> saveUsername(String username) async => _write(_keyUsername, username);
  Future<String?> getUsername() async => _read(_keyUsername);

  Future<void> savePassword(String password) async => _write(_keyPassword, password);
  Future<String?> getPassword() async => _read(_keyPassword);

  Future<void> saveAngestellteId(String id) async => _write(_keyAngestellteId, id);
  Future<String?> getAngestellteId() async => _read(_keyAngestellteId);

  Future<void> saveAssignedUserId(String id) async => _write(_keyAssignedUserId, id);
  Future<String?> getAssignedUserId() async => _read(_keyAssignedUserId);
  Future<void> saveUserId(String id) async => saveAssignedUserId(id);
  Future<String?> getUserId() async => getAssignedUserId();

  Future<void> saveAngestellteName(String name) async => _write(_keyAngestellteName, name);
  Future<String?> getAngestellteName() async => _read(_keyAngestellteName);

  Future<void> saveAcl(Map<String, dynamic> acl) async =>
      _write(_keyAclData, jsonEncode(acl));

  Future<Map<String, dynamic>> getAcl() async {
    final data = await _read(_keyAclData);
    if (data == null) return {};
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveIsAdmin(bool isAdmin) async =>
      _write(_keyIsAdmin, isAdmin.toString());

  Future<bool> getIsAdmin() async {
    final val = await _read(_keyIsAdmin);
    return val == 'true';
  }

  Future<void> saveIsAppManager(bool isAppManager) async =>
      _write(_keyIsAppManager, isAppManager.toString());

  Future<bool> getIsAppManager() async {
    final val = await _read(_keyIsAppManager);
    return val == 'true';
  }

  Future<void> saveServerUrl(String url) async => _write(_keyServerUrl, url);
  Future<String?> getServerUrl() async => _read(_keyServerUrl);

  Future<void> saveIsSammelkonto(bool val) async =>
      _write(_keyIsSammelkonto, val.toString());

  Future<bool> getIsSammelkonto() async {
    final val = await _read(_keyIsSammelkonto);
    return val == 'true';
  }

  /// Generic write – used by other parts of the app.
  Future<void> write(String key, String value) async => _write(key, value);

  /// Generic read – used by other parts of the app.
  Future<String?> read(String key) async => _read(key);

  /// Clears all stored credentials (logout).
  Future<void> deleteAll() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final keysToRemove =
          prefs.getKeys().where((k) => k.startsWith(_webPrefix)).toList();
      for (final k in keysToRemove) {
        await prefs.remove(k);
      }
    } else {
      await _secureStorage.deleteAll();
    }
  }
}
