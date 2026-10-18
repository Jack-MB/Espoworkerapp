import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/server_config.dart';
import 'secure_storage_service.dart';
import '../models/warehouse_depot.dart';
import '../models/ordnerkarte_item.dart';
import '../models/material_request.dart';

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

  /// Lädt alle für ein Depot hinterlegten Ordnerkarten und Kartennummern.
  Future<List<OrdnerkarteItem>> getDepotOrdnerkarten(String warehouseId) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/depotOrdnerkarten?warehouseId=$warehouseId');
    final headers = await _getHeaders();

    final response = await http.get(url, headers: headers).timeout(_timeout);
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      final list = (data['list'] as List?)
              ?.map((e) => OrdnerkarteItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      return list;
    } else {
      throw Exception('Fehler beim Laden der Ordnerkarten: Status ${response.statusCode}');
    }
  }

  /// Lädt den WMS-Artikelkatalog für die Materialanforderung.
  Future<Map<String, List<CatalogProduct>>> getMaterialKatalog() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/materialKatalog');
    final headers = await _getHeaders();

    final response = await http.get(url, headers: headers).timeout(_timeout);
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      final rawCats = data['categories'] as Map<String, dynamic>? ?? {};
      final Map<String, List<CatalogProduct>> result = {};

      rawCats.forEach((categoryName, items) {
        if (items is List) {
          result[categoryName] = items
              .map((item) => CatalogProduct.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      });
      return result;
    } else {
      throw Exception('Fehler beim Laden des Materialkatalogs: Status ${response.statusCode}');
    }
  }

  /// Reicht eine neue Materialanforderung über die App ein.
  Future<bool> createMaterialAnforderung({
    required String zielLagerId,
    required String bereich,
    String dringlichkeit = 'Standard',
    DateTime? benoetigtBis,
    String? begruendung,
    required List<Map<String, dynamic>> items,
  }) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/createMaterialAnforderung');
    final headers = await _getHeaders();

    final body = json.encode({
      'zielLagerId': zielLagerId,
      'bereich': bereich,
      'dringlichkeit': dringlichkeit,
      'benoetigtBis': benoetigtBis?.toIso8601String(),
      'begruendung': begruendung,
      'items': items,
    });

    final response = await http.post(url, headers: headers, body: body).timeout(_timeout);
    return response.statusCode == 200;
  }

  /// Ruft die Materialanforderungen für ein Depot oder den Benutzer ab.
  Future<List<MaterialRequestHeader>> getMyMaterialAnforderungen({String? warehouseId}) async {
    final uri = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/myMaterialAnforderungen').replace(
      queryParameters: {
        if (warehouseId != null) 'warehouseId': warehouseId,
      },
    );
    final headers = await _getHeaders();

    final response = await http.get(uri, headers: headers).timeout(_timeout);
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      final list = (data['list'] as List?)
              ?.map((e) => MaterialRequestHeader.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      return list;
    } else {
      throw Exception('Fehler beim Laden der Materialanforderungen: Status ${response.statusCode}');
    }
  }

  /// Quittiert den Wareneingang vor Ort.
  Future<bool> confirmMaterialDelivery(String anforderungId, {Map<String, double>? items}) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/confirmDelivery');
    final headers = await _getHeaders();

    final body = json.encode({
      'id': anforderungId,
      if (items != null) 'items': items,
    });

    final response = await http.post(url, headers: headers, body: body).timeout(_timeout);
    return response.statusCode == 200;
  }

  /// Lädt alle zur Ausgabe/Rücknahme relevanten Daten eines Depots (ausgegebene Gegenstände, verfügbare Ausrüstung, Katalog).
  Future<Map<String, dynamic>> getDepotHandover(String warehouseId) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/depotHandoverItems?warehouseId=$warehouseId');
    final headers = await _getHeaders();

    final response = await http.get(url, headers: headers).timeout(_timeout);
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      return {
        'canManage': data['canManage'] == true,
        'issuedItems': (data['issuedItems'] as List?) ?? [],
        'availableItems': (data['availableItems'] as List?) ?? [],
        'equipmentCatalog': (data['equipmentCatalog'] as List?) ?? [],
      };
    } else {
      throw Exception('Fehler beim Laden der Ausrüstungsdaten: Status ${response.statusCode}');
    }
  }

  /// Sucht Mitarbeiter nach Name oder Personalnummer (mit Kennzeichnung 'Heute im Dienst').
  Future<List<Map<String, dynamic>>> searchEmployees({String query = '', String? warehouseId}) async {
    final uri = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/searchEmployees').replace(
      queryParameters: {
        if (query.isNotEmpty) 'q': query,
        if (warehouseId != null) 'warehouseId': warehouseId,
      },
    );
    final headers = await _getHeaders();

    final response = await http.get(uri, headers: headers).timeout(_timeout);
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (data is Map && data['list'] is List) {
        return List<Map<String, dynamic>>.from(data['list']);
      }
    }
    return [];
  }

  /// Gibt Ausrüstung aus dem Depot an einen Mitarbeiter aus.
  Future<Map<String, dynamic>> issueDepotItem({
    required String warehouseId,
    required String productId,
    required String angestellteId,
    double quantity = 1.0,
    String? bemerkung,
    String? inventoryNumberId,
    String? signature,
  }) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/issueDepotItem');
    final headers = await _getHeaders();

    final body = json.encode({
      'warehouseId': warehouseId,
      'productId': productId,
      'angestellteId': angestellteId,
      'quantity': quantity,
      'bemerkung': bemerkung ?? 'Worker-App Ausgabe',
      if (inventoryNumberId != null) 'inventoryNumberId': inventoryNumberId,
      if (signature != null) 'signature': signature,
    });

    final response = await http.post(url, headers: headers, body: body).timeout(_timeout);
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode == 200) {
      return {'success': true, 'message': data['message'] ?? 'Erfolgreich ausgegeben.'};
    } else {
      return {'success': false, 'message': data['errorMessage'] ?? data['error'] ?? 'Fehler bei der Ausgabe (Status ${response.statusCode})'};
    }
  }

  /// Quittiert die Rücknahme von Ausrüstung zurück ins Depot.
  Future<Map<String, dynamic>> returnDepotItem({
    required String zuweisungId,
    String? warehouseId,
    String status = 'Zurückgegeben',
    String? bemerkung,
    String? signature,
  }) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/AppWarehouse/action/returnDepotItem');
    final headers = await _getHeaders();

    final body = json.encode({
      'zuweisungId': zuweisungId,
      if (warehouseId != null) 'warehouseId': warehouseId,
      'status': status,
      'bemerkung': bemerkung ?? 'Worker-App Rücknahme',
      if (signature != null) 'signature': signature,
    });

    final response = await http.post(url, headers: headers, body: body).timeout(_timeout);
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode == 200) {
      return {'success': true, 'message': data['message'] ?? 'Erfolgreich zurückgenommen.'};
    } else {
      return {'success': false, 'message': data['errorMessage'] ?? data['error'] ?? 'Fehler bei der Rücknahme (Status ${response.statusCode})'};
    }
  }
}

