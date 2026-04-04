import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  static const _keyToken = 'auth_token';
  static const _keyUsername = 'username';
  static const _keyPassword = 'password';
  static const _keyAngestellteId = 'angestellteId';
  static const _keyAssignedUserId = 'assignedUserId';
  static const _keyAngestellteName = 'angestellteName';
  static const _keyAclData = 'acl_data';
  static const _keyIsAdmin = 'is_admin';

  Future<void> saveToken(String token) async {
    await _storage.write(key: _keyToken, value: token);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _keyToken);
  }

  Future<void> saveUsername(String username) async {
    await _storage.write(key: _keyUsername, value: username);
  }

  Future<String?> getUsername() async {
    return await _storage.read(key: _keyUsername);
  }

  Future<void> savePassword(String password) async {
    await _storage.write(key: _keyPassword, value: password);
  }

  Future<String?> getPassword() async {
    return await _storage.read(key: _keyPassword);
  }

  Future<void> saveAngestellteId(String id) async {
    await _storage.write(key: _keyAngestellteId, value: id);
  }

  Future<String?> getAngestellteId() async {
    return await _storage.read(key: _keyAngestellteId);
  }

  Future<void> saveAssignedUserId(String id) async {
    await _storage.write(key: _keyAssignedUserId, value: id);
  }

  Future<String?> getAssignedUserId() async {
    return await _storage.read(key: _keyAssignedUserId);
  }

  Future<void> saveAngestellteName(String name) async {
    await _storage.write(key: _keyAngestellteName, value: name);
  }

  Future<String?> getAngestellteName() async {
    return await _storage.read(key: _keyAngestellteName);
  }

  Future<void> saveAcl(Map<String, dynamic> acl) async {
    await _storage.write(key: _keyAclData, value: jsonEncode(acl));
  }
  
  Future<Map<String, dynamic>> getAcl() async {
    final data = await _storage.read(key: _keyAclData);
    if (data == null) return {};
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) { return {}; }
  }

  Future<void> saveIsAdmin(bool isAdmin) async {
    await _storage.write(key: _keyIsAdmin, value: isAdmin.toString());
  }
  
  Future<bool> getIsAdmin() async {
    final val = await _storage.read(key: _keyIsAdmin);
    return val == 'true';
  }

  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
