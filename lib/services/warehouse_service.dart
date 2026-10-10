import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/server_config.dart';
import 'secure_storage_service.dart';
import '../models/warehouse_depot.dart';

class WarehouseService {
  final SecureStorageService _storageService = SecureStorageService();
  static const Duration _timeout = Duration(seconds: 15);
  static const String _cacheOverviewKey = 'cache_warehouse_overview_v1';

  Future<Map<String, String>> _getHeaders() async {
    final token = await _storageService.getToken();
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (token != null) {
      if (token.startsWith('Basic ')) {
        headers['Authorization'] = token;
      } else if (token.startsWith('ApiKey ')) {
        headers['X-Api-Key'] = token.replaceAll('ApiKey ', '');
      } else {
        headers['X-Auth-Token'] = token;
      }
    }
    return headers;
  }

  /// Lädt die Depot-Übersicht und persönliche Ausstattungsdaten.
  /// Nutzt lokalen Cache bei fehlender Internetverbindung.
  Future<Map<String, dynamic>> getOverview({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final cached = prefs.getString(_cacheOverviewKey);
      if (cached != null) {
        try {
          final data = json.decode(cached);
          // Im Hintergrund aktualisieren
          _fetchOverviewAndCache().catchError((e) {
            debugPrint('Silent refresh overview failed: $e');
            return <String, dynamic>{};
          });
          return _parseOverviewData(data);
        } catch (_) {}
      }
    }

    return await _fetchOverviewAndCache();
  }

  Future<Map<String, dynamic>> _fetchOverviewAndCache() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/overview');
    final headers = await _getHeaders();

    final response = await http.get(url, headers: headers).timeout(_timeout);
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheOverviewKey, json.encode(data));
      return _parseOverviewData(data);
    } else {
      throw Exception('Fehler beim Laden der Lagerdaten: Status ${response.statusCode}');
    }
  }

  Map<String, dynamic> _parseOverviewData(Map<String, dynamic> data) {
    final myDepotsList = (data['myDepots'] as List?)
            ?.map((e) => WarehouseDepot.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final allDepotsList = (data['allDepots'] as List?)
            ?.map((e) => WarehouseDepot.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final myEquipmentList = (data['myEquipment'] as List?)
            ?.map((e) => PersonalEquipmentItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final permissions = data['permissions'] as Map<String, dynamic>? ?? {};

    return {
      'myDepots': myDepotsList,
      'allDepots': allDepotsList,
      'myEquipment': myEquipmentList,
      'canManageAllDepots': permissions['canManageAllDepots'] == true,
      'canBook': permissions['canBook'] == true,
      'angestellte': data['angestellte'],
    };
  }

  /// Lädt den aktuellen Artikel- und Materialbestand eines spezifischen Depots.
  Future<List<DepotStockItem>> getDepotStock(String warehouseId) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/depotStock?warehouseId=$warehouseId');
    final headers = await _getHeaders();

    final response = await http.get(url, headers: headers).timeout(_timeout);
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      final stockItems = (data['stockItems'] as List?)
              ?.map((e) => DepotStockItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      return stockItems;
    } else {
      throw Exception('Fehler beim Laden des Depotbestands: Status ${response.statusCode}');
    }
  }

  /// Löst einen gescannten Barcode/QR-Code auf.
  Future<WarehouseScanResult> resolveScan(String code, {String? warehouseId}) async {
    final uri = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/resolveScan').replace(
      queryParameters: {
        'code': code.trim(),
        if (warehouseId != null) 'warehouseId': warehouseId,
      },
    );
    final headers = await _getHeaders();

    final response = await http.get(uri, headers: headers).timeout(_timeout);
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      return WarehouseScanResult.fromJson(data);
    } else {
      throw Exception('Scan konnte nicht aufgelöst werden: ${response.statusCode}');
    }
  }

  /// Schnelle Umbuchung / Entnahme / Rückgabe direkt vor Ort.
  Future<bool> quickBooking({
    required String productId,
    required double menge,
    String? vonLagerId,
    String? nachLagerId,
    String typ = 'Umlagerung',
    String? bemerkung,
    String? inventoryNumberId,
  }) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/quickTransfer');
    final headers = await _getHeaders();

    final body = json.encode({
      'productId': productId,
      'menge': menge,
      'vonLagerId': vonLagerId,
      'nachLagerId': nachLagerId,
      'typ': typ,
      'bemerkung': bemerkung ?? 'Worker-App Buchung',
      'inventoryNumberId': inventoryNumberId,
    });

    final response = await http.post(url, headers: headers, body: body).timeout(_timeout);
    return response.statusCode == 200;
  }

  /// Bestätigt Wäsche- oder Materialprüfung eines Depots vor Ort.
  Future<bool> confirmMaintenance(String warehouseId, String type, {String? note}) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/confirmMaintenance');
    final headers = await _getHeaders();

    final body = json.encode({
      'warehouseId': warehouseId,
      'type': type,
      'bemerkung': note ?? 'Per Worker-App quittiert',
    });

    final response = await http.post(url, headers: headers, body: body).timeout(_timeout);
    return response.statusCode == 200;
  }
}
